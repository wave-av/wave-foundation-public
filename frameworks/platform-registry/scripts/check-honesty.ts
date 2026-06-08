#!/usr/bin/env tsx
/**
 * Honesty check — the anti-vaporware gate (#291).
 *
 * The registry exists to stop a repo advertising what isn't real (see README: companion
 * modules listing actions that were never built). The other two checks cover earlier
 * layers — validate.ts enforces the SHAPE of capabilities.json, check-drift.ts enforces
 * that declared versions / binaries / cross-refs EXIST. This script enforces the next
 * honesty layer: a repo that CLAIMS an API is `metered` or sits behind real `auth` must
 * actually BACK that claim in its own source.
 *
 * Why it exists: a 2026-06-07 protocol sweep found the NDI / OMT / SRT spoke
 * capabilities.json files all advertising `metered: true` (and enforcing `auth`) over
 * surfaces that enforced nothing — bare 501 stubs and a copy-pasted NDI manifest. The
 * agent-facing discovery layer was systematically lying. This gate makes that class of
 * lie fail CI instead of shipping to agents as truth.
 *
 * The rule, per `exposes.apis[]` entry that claims `metered:true` OR `auth != "none"`:
 *
 *   HONEST iff EITHER
 *     (a) the repo's OWN source shows it backs the claim — emits usage / challenges
 *         payment (for metered), or checks a credential / principal (for auth); OR
 *     (b) the repo is a genuine gateway-fronted spoke: it declares
 *         consumes.waveProducts -> the configured gateway repo AND its source consumes the
 *         gateway-injected principal headers (x-wave-org/tier/user/gateway). The gateway
 *         enforces auth + metering at the edge, so a real fronted spoke needn't re-do it
 *         — but it MUST actually be wired to the gateway (the principal read), which a
 *         bare stub is not. This closes the "just add the gateway to consumes to keep
 *         lying" bypass.
 *   Otherwise the claim is vaporware and we flag it.
 *
 * Heuristic, deliberately biased to AVOID false alarms (broad evidence patterns): a
 * missed lie is a follow-up, but a false failure blocks an honest repo. It is rolled out
 * advisory-first via the reusable workflow's `honesty_enforce` input
 * (see workflows/validate-capabilities.yml), then flipped to blocking per-repo once green.
 *
 * Usage:
 *   tsx check-honesty.ts capabilities.json [--root <dir>]   # scan a repo (root defaults to caps dir)
 *   tsx check-honesty.ts --self-test                        # run built-in fixtures (CI dogfood)
 */

import { promises as fs } from 'node:fs';
import { dirname, join, extname } from 'node:path';
import { parseArgs } from 'node:util';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export interface ApiEntry {
  protocol?: string;
  endpoint?: string;
  auth?: string;
  metered?: boolean;
}
export interface Capabilities {
  repo?: string;
  exposes?: { apis?: ApiEntry[] };
  consumes?: { waveProducts?: { repo?: string }[] };
}
export interface Violation {
  rule: string;
  detail: string;
  fix: string;
}

/** `auth` enum values that assert real enforcement (everything except "none"). */
const ENFORCING_AUTH = new Set(['bearer-jwt', 'device-code', 'x402', 'wave-token-v1']);

// The control-plane gateway repo a spoke must declare in consumes.waveProducts to qualify as a
// "gateway-fronted" spoke. Configurable so any org can adopt this framework: set WAVE_GATEWAY_REPO
// (wired from an org-level Actions variable in validate-capabilities.yml). The literal control-plane
// repo is injected at runtime — never hardcoded here — so the published framework stays org-agnostic.
const GATEWAY_REPO = process.env.WAVE_GATEWAY_REPO ?? 'your-org/api-gateway';

// All patterns are tested against a LOWERCASED concatenation of the repo's source, so
// they are written lowercase and need no /i flag. Evidence patterns are intentionally
// broad: finding evidence SUPPRESSES a violation, so over-matching only risks a missed
// lie (a follow-up), never a false alarm against an honest repo.

/** Source really meters: emits usage to the gateway, or challenges payment (x402 / 402). */
const METER_EVIDENCE =
  /\/v1\/internal\/usage|recordusage|reportusage|wave-usage|metricscollector|paymentchallenge|x402|\b402\b|\bmeter\(/;

/** Source really enforces auth: reads a credential / principal, or rejects with 401/403. */
const AUTH_EVIDENCE =
  /x-wave-(?:org|tier|user|gateway|sub|scopes)|authorization|bearer|wave-token|requirescope|hasscope|authorize\(|www-authenticate|\b401\b|\b403\b/;

/** Proof the repo is a genuine gateway-fronted worker: it consumes the injected principal. */
const GATEWAY_PRINCIPAL = /x-wave-(?:org|tier|user|gateway)/;

/**
 * The pure core: given a parsed capabilities object and the repo's concatenated source,
 * return the honesty violations. No I/O — unit-testable via --self-test.
 */
export function findHonestyViolations(caps: Capabilities, source: string): Violation[] {
  const apis = caps.exposes?.apis ?? [];
  if (apis.length === 0) return [];

  const src = source.toLowerCase();
  const declaresGateway = (caps.consumes?.waveProducts ?? []).some((p) => p.repo === GATEWAY_REPO);
  // A real gateway-fronted spoke: declares the dependency AND is wired to read the
  // injected principal. A bare stub that merely lists the gateway repo does NOT qualify.
  const frontedByGateway = declaresGateway && GATEWAY_PRINCIPAL.test(src);

  const out: Violation[] = [];
  apis.forEach((api, i) => {
    const where = api.endpoint ? `"${api.endpoint}"` : `exposes.apis[${i}]`;

    if (api.metered === true && !METER_EVIDENCE.test(src) && !frontedByGateway) {
      out.push({
        rule: 'metered-without-meter',
        detail: `${where} declares metered:true, but the source shows no usage-emit / x402 path and the repo is not a gateway-fronted spoke`,
        fix: `set metered:false until a real meter exists (POST /v1/internal/usage, a wave-usage response header, or an x402 402 challenge) — OR declare consumes.waveProducts -> ${GATEWAY_REPO} and consume the injected x-wave-* principal`,
      });
    }

    if (api.auth && ENFORCING_AUTH.has(api.auth) && !AUTH_EVIDENCE.test(src) && !frontedByGateway) {
      out.push({
        rule: 'auth-without-enforcement',
        detail: `${where} declares auth:"${api.auth}", but the source never enforces it (no credential/principal check) and the repo is not a gateway-fronted spoke`,
        fix: `set auth:"none" until enforcement exists — OR enforce it (check Authorization / x-wave-* / call authorize()) — OR declare consumes.waveProducts -> ${GATEWAY_REPO}`,
      });
    }
  });
  return out;
}

// ── source gathering (I/O) ─────────────────────────────────────────────────────────

const CODE_EXTS = new Set(['.ts', '.tsx', '.js', '.mjs', '.cjs', '.go', '.rs', '.py', '.toml']);
const SKIP_DIR = /(^|\/)(node_modules|dist|build|\.git|vendor|coverage|\.wrangler)(\/|$)/;
const SKIP_FILE = /\.(d\.ts|test\.[tj]sx?|spec\.[tj]sx?)$/;
const MAX_FILE_BYTES = 512 * 1024;

function isScannable(path: string): boolean {
  if (SKIP_DIR.test(path) || SKIP_FILE.test(path)) return false;
  return CODE_EXTS.has(extname(path));
}

/** List the repo's tracked source files via git; fall back to a recursive walk. */
async function listSourceFiles(root: string): Promise<string[]> {
  try {
    const { stdout } = await execFileAsync('git', ['-C', root, 'ls-files'], { maxBuffer: 32 * 1024 * 1024 });
    const files = stdout.split('\n').filter((f) => f && isScannable(f)).map((f) => join(root, f));
    if (files.length > 0) return files;
  } catch {
    /* not a git checkout — walk the tree */
  }
  const acc: string[] = [];
  async function walk(dir: string): Promise<void> {
    let entries: import('node:fs').Dirent[];
    try {
      entries = await fs.readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = join(dir, e.name);
      if (SKIP_DIR.test(full)) continue;
      if (e.isDirectory()) await walk(full);
      else if (isScannable(full)) acc.push(full);
    }
  }
  await walk(root);
  return acc;
}

async function gatherSource(root: string): Promise<string> {
  const files = await listSourceFiles(root);
  const parts: string[] = [];
  for (const f of files) {
    try {
      const stat = await fs.stat(f);
      if (stat.size > MAX_FILE_BYTES) continue;
      parts.push(await fs.readFile(f, 'utf8'));
    } catch {
      /* unreadable — skip */
    }
  }
  return parts.join('\n');
}

// ── self-test (the repo has no TS test runner; this is the dogfood, run in CI) ───────

interface Fixture {
  name: string;
  caps: Capabilities;
  source: string;
  expect: string[]; // sorted rule names expected
}

const STUB = 'export default { fetch() { return new Response("hi", { status: 200 }); } };';

const FIXTURES: Fixture[] = [
  {
    name: 'lying stub — metered+auth over a bare 200 (the real NDI/OMT/SRT bug)',
    caps: {
      repo: 'wave-av/wave-ndi-edge',
      exposes: { apis: [{ protocol: 'ndi', endpoint: 'https://ndi.wave.online/feed', auth: 'wave-token-v1', metered: true }] },
    },
    source: STUB,
    expect: ['auth-without-enforcement', 'metered-without-meter'],
  },
  {
    name: 'honest scaffold — claims nothing it cannot back (the fix the sweep shipped)',
    caps: {
      repo: 'wave-av/wave-omt-edge',
      exposes: { apis: [{ protocol: 'ndi', endpoint: 'https://omt.wave.online/feed', auth: 'none', metered: false }] },
    },
    source: STUB,
    expect: [],
  },
  {
    name: 'gateway-fronted spoke — gateway meters/auths at the edge; spoke reads the principal',
    caps: {
      repo: 'example-org/clip-service',
      exposes: { apis: [{ protocol: 'http', endpoint: 'https://api.wave.online/v1/clips', auth: 'wave-token-v1', metered: true }] },
      consumes: { waveProducts: [{ repo: GATEWAY_REPO }] },
    },
    source: 'const org = request.headers.get("x-wave-org"); const tier = request.headers.get("x-wave-tier");',
    expect: [],
  },
  {
    name: 'self-metering spoke — emits usage + checks its own auth',
    caps: {
      repo: 'wave-av/some-edge',
      exposes: { apis: [{ protocol: 'http', endpoint: 'https://x.wave.online/v1/go', auth: 'bearer-jwt', metered: true }] },
    },
    source: 'await fetch("https://api.wave.online/v1/internal/usage", { method: "POST" }); const a = req.headers.get("authorization");',
    expect: [],
  },
  {
    name: 'bypass attempt — lists the gateway but never wires the principal (must still flag)',
    caps: {
      repo: 'wave-av/fake-fronted',
      exposes: { apis: [{ protocol: 'http', endpoint: 'https://y.wave.online/v1/go', metered: true }] },
      consumes: { waveProducts: [{ repo: GATEWAY_REPO }] },
    },
    source: STUB,
    expect: ['metered-without-meter'],
  },
  {
    name: 'no exposed apis (SDK/CLI repo) — nothing to check',
    caps: { repo: 'wave-av/sdk', exposes: { apis: [] } },
    source: STUB,
    expect: [],
  },
];

function runSelfTest(): number {
  let failures = 0;
  for (const fx of FIXTURES) {
    const got = findHonestyViolations(fx.caps, fx.source)
      .map((v) => v.rule)
      .sort();
    const want = [...fx.expect].sort();
    const ok = got.length === want.length && got.every((r, i) => r === want[i]);
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${fx.name}`);
    if (!ok) {
      failures++;
      console.error(`   expected: [${want.join(', ')}]`);
      console.error(`   got:      [${got.join(', ')}]`);
    }
  }
  if (failures > 0) {
    console.error(`\nself-test: ${failures} fixture(s) failed`);
    return 1;
  }
  console.log(`\nself-test: ${FIXTURES.length} fixtures passed`);
  return 0;
}

// ── CLI ──────────────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const { positionals, values } = parseArgs({
    allowPositionals: true,
    options: {
      root: { type: 'string' },
      'self-test': { type: 'boolean', default: false },
    },
  });

  if (values['self-test']) {
    process.exit(runSelfTest());
  }

  const target = positionals[0];
  if (!target) {
    console.error('usage: tsx check-honesty.ts <capabilities.json> [--root <dir>]  |  tsx check-honesty.ts --self-test');
    process.exit(2);
  }

  const caps = JSON.parse(await fs.readFile(target, 'utf8')) as Capabilities;
  const root = values.root ?? dirname(target);
  const source = await gatherSource(root);
  const violations = findHonestyViolations(caps, source);

  if (violations.length === 0) {
    console.log('honesty check: clean — every metered/auth claim is backed by enforcement or a gateway front');
    return;
  }
  console.error(`honesty check: ${violations.length} vaporware claim${violations.length === 1 ? '' : 's'}`);
  for (const v of violations) {
    console.error(`  [${v.rule}] ${v.detail}`);
    console.error(`     fix: ${v.fix}`);
  }
  process.exit(1);
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
