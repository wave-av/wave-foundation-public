#!/usr/bin/env node
// intent-ledger.mjs — the agent's durable, cross-compaction action-item memory.
//
// WHY: /compact summarizes the conversation. The summary preserves the USER's intent but
// compresses away the ASSISTANT's own surfaced ideas / "we should also" / decisions / next-steps
// — and any advisory "capture before compact" prompt depends on the agent REMEMBERING to scan.
// Across many compactions, items leak. This makes capture MECHANICAL, not cognitive: it parses
// the transcript file itself (both roles) and writes candidates to a durable ledger that a
// SessionStart hook re-surfaces. Nothing depends on the agent's working memory.
//
// It is FOR THE AGENT (automatic self-memory), not a human-facing report.
//
// FLEET NOTE: this is the wave-foundation plugin copy. The ledger defaults to a MACHINE-level
// path (~/.claude/state/intent-ledger.jsonl) — never a consumer repo's tree, never the read-only
// plugin install dir. It is the agent's cross-session memory for this machine, shared across every
// repo the plugin is installed in. Override with --ledger or $INTENT_LEDGER.
//
// Modes:
//   --capture [--transcript <path>]   parse transcript (or stdin {transcript_path}); extract
//                                     user asks + assistant commitments; dedupe vs tasks+ledger;
//                                     append new open items to the ledger.
//   --surface                         print open ledger items (SessionStart re-injection).
//   --list [--all]                    print ledger items (open by default).
//   --reconcile <id> --status <s>     close an item (done|dismissed).
//   --check                           report open-unreconciled count (exit 0).
//   --block                           exit 1 if any open-unreconciled items remain, else 0.
//   --selftest                        run the built-in invariants.
// Flags: --json, --ledger <path>, --ts <iso>, --session <id>.
// Exit:  0 ok · 1 block-fired · 64 error.

import { readFileSync, existsSync, appendFileSync, writeFileSync, mkdirSync, readdirSync, statSync, chmodSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const arg = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; };
const has = (name) => argv.includes(name);

// Machine-level default: the agent's cross-session memory, never inside a consumer repo or the
// (possibly read-only) plugin install dir. Override with --ledger or $INTENT_LEDGER.
const DEFAULT_LEDGER_DIR = join(homedir(), '.claude', 'state');
const LEDGER = arg('--ledger') || process.env.INTENT_LEDGER || join(DEFAULT_LEDGER_DIR, 'intent-ledger.jsonl');
const TASKS_ROOT = process.env.CLAUDE_TASKS_ROOT || join(homedir(), '.claude', 'tasks');

// --- normalization + id ------------------------------------------------------------
const norm = (s) => (s || '').toLowerCase().replace(/\s+/g, ' ').replace(/[`*_#>]/g, '').trim();
const idOf = (text) => createHash('sha1').update(norm(text)).digest('hex').slice(0, 12);

// Process-noise that is NOT an action item (both roles). Boilerplate around compaction/approval.
const STOP = [
  /^\/(compact|clear|copy|goto)\b/i,
  /^we just compacted/i,
  /^action (all|everything|the remaining)/i,
  /^i approve/i,
  /^continue (with )?(everything|all)/i,
  /^(yes|ok|okay|sure|thanks|thank you|great|perfect|nice)[.! ]*$/i,
  /this session is being continued/i,
  /^\(re-invocation of/i,
  /^base directory for this skill/i,
];
const isNoise = (t) => STOP.some((r) => r.test(t.trim()));

// Assistant DEFERRED-WORK lexicon — high-precision: genuine decided-but-not-done / backlog items
// that would be LOST across compaction. Deliberately NOT bare "I'll"/"next step" (those capture
// immediate this-turn narration, which is noise, not losable work).
const COMMIT = new RegExp(
  '(\\bfollow-?up\\b|\\bwe should( also)?\\b|\\bwe (also )?need to\\b|\\bdeferred?\\b|\\bTODO\\b|' +
  '\\bidea:\\b|\\bparked\\b|\\brevisit\\b|\\bbacklog\\b|\\bnext session\\b|\\bleft to do\\b|' +
  '\\bstill (need|needs) to\\b|\\bnot yet (done|built|wired|shipped|landed|merged)\\b|' +
  '\\bbank (it|this|that) as\\b|\\bas a follow-?up\\b|\\bworth .{0,30}later\\b|\\block it in later\\b)',
  'i'
);
// Transient status narration — drop even if a COMMIT phrase matches (self-resolving, not losable).
const TRANSIENT = /(I'll report|I'll bring you|I'll let you know|report (the moment|when|once)|no action needed|the moment it (lands|completes|finishes|merges)|while it (runs|does)|in the background|standing by|stay tuned)/i;

// --- transcript parsing ------------------------------------------------------------
function textOf(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content.filter((b) => b && b.type === 'text').map((b) => b.text || '').join('\n');
  }
  return '';
}

// Extract candidate items from transcript JSONL lines. Pure: returns array, no I/O.
export function extractCandidates(rawLines, { session = '' } = {}) {
  const out = [];
  for (const line of rawLines) {
    let o;
    try { o = JSON.parse(line); } catch { continue; }
    if (o.isSidechain) continue; // skip subagent-internal turns
    const m = o.message;
    if (!m) continue;
    const role = m.role || o.type;
    const text = textOf(m.content).trim();
    if (!text) continue;
    const ts = (o.timestamp || '').slice(0, 19);
    if (role === 'user') {
      // Skip tool_result-only turns, hook/system noise, and boilerplate.
      if (Array.isArray(m.content) && m.content.some((b) => b && b.type === 'tool_result')) continue;
      if (/system-reminder|hook additional context|local-command|<command-name|task-notification|Caveat: The messages/.test(text)) continue;
      if (isNoise(text)) continue;
      // Skip pasted-back assistant wrap-ups (the user re-feeding prior context after /compact):
      // markdown headings/status-emoji openers, or tell-tale summary phrasing — these are echoes,
      // not fresh asks.
      if (/^\s*(#{1,3}\s|[✅🎯🚀🔧🧾]|\*\*(Done|Everything|Shipped|Complete))/.test(text)) continue;
      if (/(actionable (is|by me) )?(is )?complete|honest final state|proven[- ]live|all gates?-?green/i.test(text) && text.length > 160) continue;
      if (text.length < 12) continue; // trivial acks
      out.push({ id: idOf(text), ts, session, role: 'user', kind: 'user-ask', text: clip(text) });
    } else if (role === 'assistant') {
      // Split into sentence-ish units; keep those that carry a forward-looking commitment.
      for (const sent of splitSentences(text)) {
        if (sent.length < 15 || sent.length > 240) continue;
        if (isNoise(sent) || TRANSIENT.test(sent)) continue;
        if (COMMIT.test(sent)) {
          out.push({ id: idOf(sent), ts, session, role: 'assistant', kind: 'assistant-commitment', text: clip(sent) });
        }
      }
    }
  }
  // dedupe within this extraction by id
  const seen = new Set();
  return out.filter((c) => (seen.has(c.id) ? false : (seen.add(c.id), true)));
}

const clip = (s) => (s.length > 240 ? s.slice(0, 237) + '…' : s).replace(/\n+/g, ' ').trim();
function splitSentences(text) {
  return text
    .split(/\n+/).flatMap((para) => para.split(/(?<=[.!?:])\s+(?=[A-Z(`\-\d])/))
    .map((s) => s.trim()).filter(Boolean);
}

// --- ledger + tasks I/O ------------------------------------------------------------
export function readLedger(path = LEDGER) {
  if (!existsSync(path)) return [];
  return readFileSync(path, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
}

// Gather normalized text of every existing task (subject+description) for dedupe.
function existingTaskText(root = TASKS_ROOT) {
  const blobs = [];
  try {
    for (const sess of readdirSync(root)) {
      const dir = join(root, sess);
      let st; try { st = statSync(dir); } catch { continue; }
      if (!st.isDirectory()) continue;
      for (const f of readdirSync(dir)) {
        if (!f.endsWith('.json')) continue;
        try {
          const t = JSON.parse(readFileSync(join(dir, f), 'utf8'));
          blobs.push(norm(`${t.subject || ''} ${t.description || ''}`));
        } catch { /* skip */ }
      }
    }
  } catch { /* no tasks dir */ }
  return blobs;
}

// A candidate is already-tracked if its id is in the ledger, or its normalized text is
// substantially contained in an existing task blob (conservative: over-capture beats loss).
export function dedupe(cands, { ledger = [], taskBlobs = [] } = {}) {
  const ledgerIds = new Set(ledger.map((e) => e.id));
  return cands.filter((c) => {
    if (ledgerIds.has(c.id)) return false;
    const n = norm(c.text);
    if (n.length >= 20 && taskBlobs.some((b) => b.includes(n))) return false;
    return true;
  });
}

// The ledger holds action items clipped VERBATIM from session transcripts — user asks, in-flight
// work, assistant commitments. Under a common umask, default process permissions create a 0755
// directory and a 0644 file, so every other local user on a shared developer or CI host can read
// it. Corridor flagged this as CWE-276 and it was confirmed live: 1.1 MB at 0644 under a 0755 dir.
const LEDGER_DIR_MODE = 0o700;
const LEDGER_FILE_MODE = 0o600;

// Creating with a `mode` is NOT sufficient, for two independent reasons: the mode is masked by the
// umask, and it is ignored outright when the path already exists. Neither mkdir nor open would have
// touched the 1.1 MB ledger already sitting at 0644 — so the bits have to be narrowed explicitly.
//
// NARROWING ONLY, by construction: the new permission bits are `current & allowed`, which can
// only clear bits, never set them. A ledger someone has deliberately locked down further stays
// that way, and no input to this function can widen a path. The special bits (setuid/setgid/
// sticky) are preserved verbatim: chmod(2) takes the FULL mode, so passing only the low 9 bits
// would silently strip e.g. the setgid bit off a group-shared directory or the sticky bit off a
// /tmp-like directory (a behavior change beyond narrowing). Best-effort because it runs on every
// SessionStart and PreCompact: an EPERM on a path owned by another user must not take the hook down.
export function narrowPermissions(path, allowed) {
  try {
    const mode = statSync(path).mode & 0o7777;
    const current = mode & 0o777;
    if ((current & ~allowed) !== 0) chmodSync(path, (mode & 0o7000) | (current & allowed));
  } catch { /* absent, or not ours to chmod — nothing to narrow */ }
}

// Narrow the ledger's parent directory ONLY when it is ours: the machine-level default state dir
// (the already-deployed ledgers the CWE-276 finding is about), or a directory this call just
// created. The ledger path is user-configurable (--ledger / $INTENT_LEDGER), so dirname(path) can
// be $HOME, /tmp, or a shared project dir; tightening a directory the hook does not own would
// revoke access other users and tools legitimately have. The ledger FILE itself is always ours
// and is narrowed unconditionally by the writers.
function ensureLedgerDir(path) {
  const dir = dirname(path);
  const created = mkdirSync(dir, { recursive: true, mode: LEDGER_DIR_MODE });
  if (created !== undefined || resolve(dir) === DEFAULT_LEDGER_DIR) narrowPermissions(dir, LEDGER_DIR_MODE);
}

export function writeLedger(entries, path = LEDGER) {
  ensureLedgerDir(path);
  writeFileSync(path, entries.map((e) => JSON.stringify(e)).join('\n') + (entries.length ? '\n' : ''), { mode: LEDGER_FILE_MODE });
  narrowPermissions(path, LEDGER_FILE_MODE);
}
export function appendLedger(entries, path = LEDGER) {
  if (!entries.length) {
    // Even a no-op capture must remediate. On a machine where every PreCompact dedupes to zero
    // fresh items, an early return here would leave a pre-existing world-readable ledger wide
    // indefinitely: --surface never writes, and this is the only writer that runs routinely.
    narrowPermissions(path, LEDGER_FILE_MODE);
    if (resolve(dirname(path)) === DEFAULT_LEDGER_DIR) narrowPermissions(dirname(path), LEDGER_DIR_MODE);
    return;
  }
  ensureLedgerDir(path);
  appendFileSync(path, entries.map((e) => JSON.stringify(e)).join('\n') + '\n', { mode: LEDGER_FILE_MODE });
  narrowPermissions(path, LEDGER_FILE_MODE);
}

// --- modes -------------------------------------------------------------------------
function readStdinSync() {
  try { return readFileSync(0, 'utf8'); } catch { return ''; }
}
function resolveTranscript() {
  const t = arg('--transcript');
  if (t) return t;
  const raw = readStdinSync();
  if (raw) { try { const j = JSON.parse(raw); if (j.transcript_path) return j.transcript_path; } catch { /* not json */ } }
  return '';
}

function capture() {
  const path = resolveTranscript();
  if (!path || !existsSync(path)) { console.error(`intent-ledger: no transcript (${path || 'none'}) — nothing to capture`); return 0; }
  const session = arg('--session') || (path.split('/').pop() || '').replace('.jsonl', '');
  const lines = readFileSync(path, 'utf8').split('\n').filter(Boolean);
  const cands = extractCandidates(lines, { session });
  const fresh = dedupe(cands, { ledger: readLedger(), taskBlobs: existingTaskText() });
  const stamped = fresh.map((c) => ({ ...c, capturedAt: arg('--ts') || new Date().toISOString(), status: 'open' }));
  appendLedger(stamped);
  const payload = { captured: stamped.length, scanned: cands.length, ledger: LEDGER };
  console.log(has('--json') ? JSON.stringify(payload) : `intent-ledger: captured ${stamped.length} new (of ${cands.length} candidates) → ${LEDGER}`);
  return 0;
}

function openItems() { return readLedger().filter((e) => e.status === 'open'); }

function surface() {
  const open = openItems();
  if (has('--json')) { console.log(JSON.stringify(open)); return 0; }
  if (!open.length) { console.log('🧾 intent-ledger: no open action items.'); return 0; }
  console.log(`🧾 INTENT LEDGER — ${open.length} open action item(s) carried across compaction:`);
  for (const e of open) console.log(`  • [${e.id}] (${e.kind}) ${e.text}`);
  console.log('  Reconcile each: promote it to an issue, or `intent-ledger.mjs --reconcile <id> --status dismissed`.');
  return 0;
}

function list() {
  const items = has('--all') ? readLedger() : openItems();
  console.log(has('--json') ? JSON.stringify(items) : items.map((e) => `[${e.id}] ${e.status}\t(${e.kind}) ${e.text}`).join('\n') || '(empty)');
  return 0;
}

function reconcile() {
  const id = arg('--reconcile');
  const status = arg('--status') || 'done';
  if (!id) { console.error('intent-ledger: --reconcile needs an <id>'); return 64; }
  if (!['done', 'dismissed'].includes(status)) { console.error('intent-ledger: --status must be done|dismissed'); return 64; }
  const all = readLedger();
  const hit = all.find((e) => e.id === id);
  if (!hit) { console.error(`intent-ledger: no ledger item ${id}`); return 64; }
  hit.status = status; hit.reconciledAt = arg('--ts') || new Date().toISOString();
  writeLedger(all);
  console.log(`intent-ledger: ${id} → ${status}`);
  return 0;
}

function check() {
  const n = openItems().length;
  console.log(has('--json') ? JSON.stringify({ open: n }) : `intent-ledger: ${n} open unreconciled item(s)`);
  return 0;
}

function block() {
  const open = openItems();
  if (open.length) {
    console.error(`intent-ledger: BLOCK — ${open.length} unreconciled action item(s) must be reconciled before compaction:`);
    for (const e of open) console.error(`  • [${e.id}] ${e.text}`);
    return 1;
  }
  console.log('intent-ledger: clean — no unreconciled items.');
  return 0;
}

function selftest() {
  const fixture = [
    JSON.stringify({ type: 'user', message: { role: 'user', content: 'Please build the widget exporter in lib/export.ts' }, timestamp: '2026-07-10T00:00:00Z' }),
    JSON.stringify({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: "That part is done. Follow-up: we should also wire the retry loop into the queue consumer." }] }, timestamp: '2026-07-10T00:01:00Z' }),
    JSON.stringify({ type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: "All green — I'll report the moment the deploy completes." }] }, timestamp: '2026-07-10T00:01:30Z' }),
    JSON.stringify({ type: 'user', message: { role: 'user', content: 'we just compacted, action all the remaining tasks' }, timestamp: '2026-07-10T00:02:00Z' }),
    JSON.stringify({ isSidechain: true, type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: "I'll ignore this subagent line." }] } }),
  ];
  const c = extractCandidates(fixture, { session: 'test' });
  const assert = (cond, msg) => { if (!cond) { console.error('SELFTEST FAIL:', msg); process.exit(1); } };
  assert(c.some((x) => x.kind === 'user-ask' && /widget exporter/.test(x.text)), 'user ask not captured');
  assert(c.some((x) => x.kind === 'assistant-commitment' && /retry loop/.test(x.text)), 'assistant commitment not captured');
  assert(!c.some((x) => /deploy completes/.test(x.text)), 'transient status narration not excluded');
  assert(!c.some((x) => /remaining tasks/.test(x.text)), 'boilerplate not filtered');
  assert(!c.some((x) => /subagent line/.test(x.text)), 'sidechain not skipped');
  const d = dedupe(c, { ledger: [{ id: c[0].id }], taskBlobs: [] });
  assert(!d.some((x) => x.id === c[0].id), 'ledger dedupe failed');
  console.log('intent-ledger selftest: PASS');
  return 0;
}

// --- CLI dispatch ------------------------------------------------------------------
function main() {
  if (has('--selftest')) return selftest();
  if (has('--capture')) return capture();
  if (has('--surface')) return surface();
  if (has('--list')) return list();
  if (has('--reconcile')) return reconcile();
  if (has('--check')) return check();
  if (has('--block')) return block();
  console.error('intent-ledger: specify a mode (--capture|--surface|--list|--reconcile|--check|--block|--selftest)');
  return 64;
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main());
