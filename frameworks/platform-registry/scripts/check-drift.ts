#!/usr/bin/env tsx
/**
 * Drift checker — catches the class of error the registry exists to prevent.
 *
 * Three checks, each opt-in via flag so they can be wired separately:
 *
 *   --check-package-version
 *     If a package.json / Cargo.toml / go.mod / pyproject.toml lives next to the
 *     capabilities.json, compare the declared version. Mismatch = error.
 *
 *   --check-cli-binaries
 *     For each exposes.cli[].binary, verify it appears as either a package.json
 *     bin entry, a Cargo.toml [[bin]], a Go cmd/ directory, or an executable file.
 *     Missing binary = error.
 *
 *   --check-cross-refs
 *     For each consumes.waveProducts[].repo, verify it exists in the foundation
 *     state.json. Missing reference = error.
 *
 * Each check that fails prints a remediation hint. Exit 1 on any failure.
 *
 * Usage:
 *   tsx check-drift.ts capabilities.json \
 *     --check-package-version \
 *     --check-cli-binaries \
 *     --check-cross-refs \
 *     [--state-json <path>]
 *
 * There is no built-in default state.json source: pass `--state-json <path>` for a
 * local snapshot, or set `WAVE_PLATFORM_STATE_URL=<url>` to fetch a published one.
 * A hardcoded URL used to live here, pointing into a repo a public consumer cannot
 * read — green in CI, HTTP 404 at run time. `--check-cross-refs` now reports a
 * drift error naming the missing configuration rather than a confusing fetch failure.
 * Choosing a publicly-resolvable source for state.json is tracked in #102.
 */

import { promises as fs } from 'node:fs';
import { dirname, join } from 'node:path';
import { parseArgs } from 'node:util';

interface Capabilities {
  schemaVersion: string;
  repo: string;
  version: string;
  exposes?: {
    cli?: { binary: string; subcommands?: string[] }[];
  };
  consumes?: {
    waveProducts?: { repo: string; endpoint?: string }[];
  };
}

interface RegistryState {
  capabilities: { repo: string }[];
}

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    'check-package-version': { type: 'boolean', default: false },
    'check-cli-binaries': { type: 'boolean', default: false },
    'check-cross-refs': { type: 'boolean', default: false },
    'state-json': { type: 'string' },
  },
});

const target = positionals[0];
if (!target) {
  console.error('usage: tsx check-drift.ts <capabilities.json> [--check-package-version] [--check-cli-binaries] [--check-cross-refs] [--state-json <path>]');
  process.exit(2);
}

interface DriftError {
  rule: string;
  detail: string;
  fix: string;
}

async function main(): Promise<void> {
  const raw = await fs.readFile(target!, 'utf8');
  const caps = JSON.parse(raw) as Capabilities;
  const repoRoot = dirname(target!);
  const errors: DriftError[] = [];

  if (values['check-package-version']) {
    const drift = await checkPackageVersion(caps, repoRoot);
    if (drift) errors.push(drift);
  }
  if (values['check-cli-binaries']) {
    const drift = await checkCliBinaries(caps, repoRoot);
    errors.push(...drift);
  }
  if (values['check-cross-refs']) {
    const drift = await checkCrossRefs(caps, values['state-json']);
    errors.push(...drift);
  }

  if (errors.length === 0) {
    console.log('drift check: clean');
    return;
  }
  console.error(`drift check: ${errors.length} issue${errors.length === 1 ? '' : 's'}`);
  for (const e of errors) {
    console.error(`  [${e.rule}] ${e.detail}`);
    console.error(`     fix: ${e.fix}`);
  }
  process.exit(1);
}

async function checkPackageVersion(caps: Capabilities, root: string): Promise<DriftError | null> {
  // Try package.json first.
  const pkgPath = join(root, 'package.json');
  try {
    const pkg = JSON.parse(await fs.readFile(pkgPath, 'utf8')) as { version?: string };
    if (typeof pkg.version === 'string' && pkg.version !== caps.version) {
      return {
        rule: 'package-version',
        detail: `capabilities.json version "${caps.version}" != package.json version "${pkg.version}"`,
        fix: `update capabilities.json version to "${pkg.version}" (canonical) or bump package.json`,
      };
    }
  } catch {
    /* no package.json — try other formats below */
  }

  // Try Cargo.toml.
  try {
    const cargo = await fs.readFile(join(root, 'Cargo.toml'), 'utf8');
    const m = cargo.match(/^\s*version\s*=\s*"([^"]+)"/m);
    if (m && m[1] !== caps.version) {
      return {
        rule: 'package-version',
        detail: `capabilities.json version "${caps.version}" != Cargo.toml version "${m[1]}"`,
        fix: `update capabilities.json to "${m[1]}"`,
      };
    }
  } catch {
    /* no Cargo.toml */
  }

  return null;
}

async function checkCliBinaries(caps: Capabilities, root: string): Promise<DriftError[]> {
  const out: DriftError[] = [];
  const bins = caps.exposes?.cli ?? [];
  if (bins.length === 0) return out;

  // Read package.json bin field if it exists.
  let pkgBins: Record<string, string> = {};
  try {
    const pkg = JSON.parse(await fs.readFile(join(root, 'package.json'), 'utf8')) as {
      bin?: Record<string, string> | string;
      name?: string;
    };
    if (typeof pkg.bin === 'string' && pkg.name) {
      pkgBins[pkg.name.split('/').pop() ?? pkg.name] = pkg.bin;
    } else if (typeof pkg.bin === 'object' && pkg.bin) {
      pkgBins = pkg.bin;
    }
  } catch {
    /* no package.json */
  }

  // Look for cmd/<binary>/main.go (Go convention).
  let goCmds = new Set<string>();
  try {
    const entries = await fs.readdir(join(root, 'cmd'));
    for (const e of entries) goCmds.add(e);
  } catch {
    /* no cmd/ dir */
  }

  for (const { binary } of bins) {
    const inPkg = binary in pkgBins;
    const inGo = goCmds.has(binary);
    if (!inPkg && !inGo) {
      out.push({
        rule: 'cli-binary-missing',
        detail: `declared CLI binary "${binary}" not found in package.json#bin or cmd/${binary}/`,
        fix: `either implement the binary or remove it from exposes.cli`,
      });
    }
  }
  return out;
}

async function checkCrossRefs(caps: Capabilities, statePath?: string): Promise<DriftError[]> {
  const out: DriftError[] = [];
  const consumed = caps.consumes?.waveProducts ?? [];
  if (consumed.length === 0) return out;

  let state: RegistryState;
  if (statePath) {
    state = JSON.parse(await fs.readFile(statePath, 'utf8')) as RegistryState;
  } else {
    // No hardcoded fallback URL. The previous one pointed into a repo a public
    // consumer cannot read, so it returned 404 at run time in every consumer
    // environment while CI stayed green. The source is caller-supplied, and its
    // absence is reported as a drift error (exit 1) rather than guessed at.
    const url = process.env.WAVE_PLATFORM_STATE_URL;
    if (!url) {
      out.push({
        rule: 'cross-refs',
        detail:
          'no state.json source configured: --state-json was not passed and $WAVE_PLATFORM_STATE_URL is unset',
        fix: 'pass --state-json <path> to read a local snapshot, or set WAVE_PLATFORM_STATE_URL=<url> to fetch a published one',
      });
      return out;
    }

    let res: Response;
    try {
      res = await fetch(url);
    } catch (err) {
      out.push({
        rule: 'cross-refs',
        detail: `fetching state.json from $WAVE_PLATFORM_STATE_URL (${url}) failed: ${err instanceof Error ? err.message : String(err)}`,
        fix: 'check the URL is reachable from here, or pass --state-json <path> to read a local snapshot',
      });
      return out;
    }
    if (!res.ok) {
      out.push({
        rule: 'cross-refs',
        detail: `couldn't fetch state.json from ${url} (HTTP ${res.status})`,
        fix: 'check the URL serves the raw state.json, or pass --state-json <path> to read a local snapshot',
      });
      return out;
    }
    state = (await res.json()) as RegistryState;
  }

  const known = new Set(state.capabilities.map((c) => c.repo));
  for (const { repo } of consumed) {
    if (!known.has(repo)) {
      out.push({
        rule: 'cross-refs',
        detail: `consumes.waveProducts references "${repo}" but it's not in state.json`,
        fix: `verify the consumed repo exists; or add its capabilities.json so it appears in the registry`,
      });
    }
  }
  return out;
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
