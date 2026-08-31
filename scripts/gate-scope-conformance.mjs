#!/usr/bin/env node
// Gate-scope conformance: do all copies of the file-size law's two lists still agree?
//
// rules/file-size-limits.md is enforced by FOUR independent, hand-maintained copies of the same
// two lists in this repo, and nothing compares them:
//
//   1. .github/workflows/checks.yml  "File-size gate"                 (line cap, whole-tree)
//   2. .github/workflows/checks.yml  "Token-budget gate"              (byte cap, diff-scoped, INLINED)
//   3. scripts/gen-token-budget-baseline.sh                           (seeds the baseline)
//   4. scripts/token-budget-check-changed.sh                          (the "local/tested reference")
//
// The two lists are:
//   SCAN SET — the extension globs in the pathspec of whatever lists files (`git ls-files` /
//              `git diff … -- …`). An extension absent here CANNOT be failed by that gate.
//   SKIP SET — the `case` arms whose body is `continue`. A path absent here CANNOT be exempted.
//
// Drift between copies is not cosmetic:
//   • An extension in a GATE but not in the GENERATOR can never enter a baseline, so it can never
//     be grandfathered — it lands in the gate's "NEW oversized file" branch and hard-fails on first
//     touch. That is why "land the baseline first" does not work unless the generator moves too.
//   • An extension in NO gate is unenforceable everywhere, however loudly a local hook nags about it.
//   • checks.yml:96 asks a human to "keep this inlined copy behaviorally in sync" with (4).
//     A comment is not a mechanism. This script is the mechanism.
//
// Static and hermetic: reads files, runs no gate, opens no socket, writes nothing, needs no token.
//
// Usage:
//   node scripts/gate-scope-conformance.mjs [--dir <repo>] [--ref <git-ref>] [--json]
// Exit: 0 = all copies agree · 1 = drift or unreadable source · 2 = usage error

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const SOURCES = [
  { rel: '.github/workflows/checks.yml', kind: 'workflow' },
  { rel: 'scripts/gen-token-budget-baseline.sh', kind: 'shell' },
  { rel: 'scripts/token-budget-check-changed.sh', kind: 'shell' },
];

/** Quoted tokens, single or double. Two flat alternatives — no nested quantifier, linear time. */
function quotedTokens(s) {
  const out = [];
  for (const m of s.matchAll(/'([^']*)'|"([^"]*)"/g)) out.push(m[1] !== undefined ? m[1] : m[2]);
  return out;
}

const GLOB = /^\*\.[A-Za-z0-9]+$/;

/**
 * A size gate is identified by BEHAVIOUR — a block that MEASURES SIZE (`wc -l` / `wc -c`) — never
 * by its step name. Renaming a step must not blind this checker; that is the failure mode that let
 * the drift accumulate unseen in the first place.
 */
function sizeGateBlocks(text, label, kind) {
  if (kind !== 'workflow') {
    return /\bwc\s+-[lc]\b/.test(text) ? [{ name: label, text }] : [];
  }
  const steps = [];
  let cur = null;
  for (const line of text.split('\n')) {
    const m = line.match(/^\s*- name:\s*(.+)$/);
    if (m) {
      if (cur) steps.push(cur);
      cur = { name: m[1].trim(), body: [] };
      continue;
    }
    if (cur) cur.body.push(line);
  }
  if (cur) steps.push(cur);
  return steps
    .map((s) => ({ name: `${label}: ${s.name}`, text: s.body.join('\n') }))
    .filter((b) => /\bwc\s+-[lc]\b/.test(b.text));
}

/**
 * Shell continues a logical line with a trailing backslash. A line-oriented parser that ignores
 * that reads only the FINAL physical line of a wrapped `case` arm — and a truncated set silently
 * "agrees" with every other truncated set, which is fail-OPEN.
 *
 * This is not hypothetical: reformatting a 16-pattern skip arm across four lines made this checker
 * report agreement on 2 patterns. Joining first is what makes the extraction independent of how the
 * shell happens to be wrapped, which is the same principle as identifying gates by behaviour rather
 * than by name.
 */
function logicalLines(text) {
  const out = [];
  let acc = null;
  for (const raw of text.split('\n')) {
    const continued = /\\\s*$/.test(raw);
    const body = raw.replace(/\\\s*$/, '');
    acc = acc === null ? body : `${acc} ${body.trim()}`;
    if (!continued) {
      out.push(acc);
      acc = null;
    }
  }
  if (acc !== null) out.push(acc); // trailing backslash at EOF — keep what we have
  return out;
}

/** SCAN SET: extension globs in the pathspec of whatever lists files. */
function scanSet(blockText) {
  const exts = new Set();
  let sawLister = false;
  for (const raw of logicalLines(blockText)) {
    const line = raw.replace(/\s#.*$/, '');
    const i = line.search(/git\s+(ls-files|diff)\b/);
    if (i < 0) continue;
    let tail = line.slice(i);
    if (/^git\s+diff\b/.test(tail)) {
      // For `git diff`, only the pathspec AFTER the standalone `--` is a path filter; anything
      // before it is a revision. Without this the `--name-only`/`--diff-filter` flags would parse
      // as scan-set members.
      const sep = tail.indexOf(' -- ');
      if (sep < 0) continue;
      tail = tail.slice(sep + 4);
    }
    sawLister = true;
    for (const t of quotedTokens(tail)) if (GLOB.test(t)) exts.add(t.slice(1));
  }
  return { exts, sawLister };
}

/** SKIP SET: `case` arms whose body is `continue`. */
function skipSet(blockText) {
  const pats = new Set();
  for (const raw of logicalLines(blockText)) {
    const line = raw.replace(/\s#.*$/, '');
    const k = line.indexOf(') continue');
    if (k < 0) continue;
    let arm = line.slice(0, k);
    const inIdx = arm.lastIndexOf(' in '); // `case "$f" in staging/*) continue ;; esac` on one line
    if (inIdx >= 0) arm = arm.slice(inIdx + 4);
    for (const p of arm.split('|').map((s) => s.trim())) {
      // `*AUTO-GENERATED*` matches file CONTENT (line 1), not a path — a different axis entirely.
      if (p && p !== '*' && !p.includes('AUTO-GENERATED')) pats.add(p);
    }
  }
  return pats;
}

function readSource(dir, ref, rel) {
  try {
    if (ref) {
      return execFileSync('git', ['-C', dir, 'show', `${ref}:${rel}`], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        maxBuffer: 32 * 1024 * 1024,
      });
    }
    return readFileSync(join(dir, rel), 'utf8');
  } catch {
    return null;
  }
}

const sorted = (set) => [...set].sort();
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

function main(argv) {
  let dir = process.cwd();
  let ref = null;
  let json = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--dir') dir = argv[++i];
    else if (argv[i] === '--ref') ref = argv[++i];
    else if (argv[i] === '--json') json = true;
    else {
      process.stderr.write(`usage: gate-scope-conformance.mjs [--dir <repo>] [--ref <ref>] [--json]\n`);
      return 2;
    }
  }
  if (!dir) return 2;

  const checks = [];
  const add = (name, ok, detail) => checks.push({ name, ok, detail });

  // ---- read every source; an unreadable source is a FAILURE, never a skip -------------------
  const texts = [];
  let allRead = true;
  for (const s of SOURCES) {
    const t = readSource(dir, ref, s.rel);
    if (t === null) allRead = false;
    else texts.push({ ...s, text: t });
  }
  add(
    'sources-readable',
    allRead,
    allRead ? `${SOURCES.length} source(s) read` : `unreadable: ${SOURCES.filter((s) => !texts.some((t) => t.rel === s.rel)).map((s) => s.rel).join(', ')}`,
  );

  // Each check below is a conclusion DRAWN FROM the premise above it. When a premise fails, report
  // THAT and stop: a checker that cannot read its sources knows nothing about their conformance,
  // and an empty set trivially "agrees" with itself. Reporting derived checks here would bury the
  // real cause under noise that is technically true and practically misleading.
  if (!allRead) return emit(checks, json, []);

  // ---- locate the size gates BY BEHAVIOUR ---------------------------------------------------
  // EVERY source must contribute at least one size-measuring block. Counting blocks in aggregate
  // is not enough: checks.yml contributes two, so a shell source that stops measuring size would
  // still leave the total at or above the source count and slip through unnoticed.
  const perSource = texts.map((t) => ({ rel: t.rel, found: sizeGateBlocks(t.text, t.rel, t.kind) }));
  const barren = perSource.filter((p) => p.found.length === 0);
  const blocks = perSource.flatMap((p) => p.found);
  const located = barren.length === 0;
  add(
    'gates-located',
    located,
    located
      ? `${blocks.length} size-measuring block(s): ${blocks.map((b) => b.name).join(' | ')}`
      : `no size-measuring block found in: ${barren.map((p) => p.rel).join(', ')}`,
  );

  if (!located) return emit(checks, json, blocks);

  const parsed = blocks.map((b) => {
    const { exts, sawLister } = scanSet(b.text);
    return { name: b.name, exts, sawLister, skips: skipSet(b.text) };
  });

  // ---- FAIL-CLOSED: an empty extraction agrees with everything -------------------------------
  const noScan = parsed.filter((p) => !p.sawLister || p.exts.size === 0);
  add(
    'scan-sets-extracted',
    noScan.length === 0,
    noScan.length === 0
      ? 'every gate yielded a non-empty scan set'
      : `no scan set extracted from: ${noScan.map((p) => p.name).join(', ')}`,
  );

  const noSkip = parsed.filter((p) => p.skips.size === 0);
  add(
    'skip-sets-extracted',
    noSkip.length === 0,
    noSkip.length === 0
      ? 'every gate yielded a non-empty skip set'
      : `no skip set extracted from: ${noSkip.map((p) => p.name).join(', ')}`,
  );

  if (noScan.length || noSkip.length) return emit(checks, json, blocks);

  // ---- the actual conformance assertions -----------------------------------------------------
  const scans = parsed.map((p) => ({ name: p.name, list: sorted(p.exts) }));
  const scanAgree = scans.every((s) => same(s.list, scans[0].list));
  add(
    'scan-sets-agree',
    scanAgree,
    scanAgree
      ? `all gates scan: ${scans[0].list.join(' ')}`
      : scans.map((s) => `\n      ${s.name.padEnd(52)} ${s.list.join(' ')}`).join(''),
  );

  const skipsL = parsed.map((p) => ({ name: p.name, list: sorted(p.skips) }));
  const skipAgree = skipsL.every((s) => same(s.list, skipsL[0].list));
  add(
    'skip-sets-agree',
    skipAgree,
    skipAgree
      ? `all gates exempt: ${skipsL[0].list.join(' ')}`
      : skipsL.map((s) => `\n      ${s.name.padEnd(52)} ${s.list.join(' ')}`).join(''),
  );

  // The asymmetric direction is the one that bites: an extension a GATE scans but the GENERATOR
  // does not can never be baselined, so it can never be grandfathered.
  if (!scanAgree) {
    const gen = parsed.find((p) => p.name.includes('gen-token-budget-baseline'));
    if (gen) {
      const ungrandfatherable = [
        ...new Set(parsed.filter((p) => p !== gen).flatMap((p) => [...p.exts])),
      ]
        .filter((e) => !gen.exts.has(e))
        .sort();
      if (ungrandfatherable.length) {
        add(
          'gated-extensions-are-baselineable',
          false,
          `scanned by a gate but NOT by the baseline generator, so never grandfathered: ${ungrandfatherable.join(' ')}`,
        );
      }
    }
  }

  return emit(checks, json, blocks);
}

function emit(checks, json, blocks) {
  const failed = checks.filter((c) => !c.ok);
  if (json) {
    process.stdout.write(
      `${JSON.stringify({ ok: failed.length === 0, checks, gates: blocks.map((b) => b.name) }, null, 2)}\n`,
    );
  } else {
    for (const c of checks) process.stdout.write(`${c.ok ? '✅' : '❌'} ${c.name}\n      ${c.detail}\n`);
    process.stdout.write(
      failed.length === 0
        ? '\ngate-scope conformance: all copies of the scan/skip sets agree\n'
        : `\ngate-scope conformance: ${failed.length} check(s) failed — see rules/file-size-limits.md and claude-workstation#586\n`,
    );
  }
  return failed.length === 0 ? 0 : 1;
}

process.exit(main(process.argv.slice(2)));
