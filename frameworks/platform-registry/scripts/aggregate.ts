#!/usr/bin/env tsx
/**
 * Aggregate every wave-av repo's capabilities.json into a single state.json
 * + a human-readable STATE.md.
 *
 * Run via the registry-aggregate.yml workflow on each foundation push and
 * every six hours. The workflow shells in the GH API to fetch each repo's
 * /capabilities.json at its master HEAD; this script just consumes the
 * already-downloaded files from a local directory.
 *
 * Usage:
 *   tsx aggregate.ts --in /tmp/caps --out frameworks/platform-registry
 *
 * Inputs (--in):
 *   /tmp/caps/wave-monitor.json
 *   /tmp/caps/wave-desktop.json
 *   ...
 *
 * Outputs (--out):
 *   state.json   machine-readable union of every input + meta (timestamp, count)
 *   STATE.md     auto-generated human-readable rollup, grouped by plane layer
 */

import { promises as fs } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

interface Capabilities {
  schemaVersion: string;
  repo: string;
  version: string;
  lifecycle: 'alpha' | 'beta' | 'ga' | 'sunsetting' | 'archived';
  planeLayer: number | null;
  foundationPin?: string;
  maintainers?: { team: string; onCallRotation?: string }[];
  exposes?: {
    apis?: { protocol: string; endpoint: string; openapiRef?: string; auth?: string; metered?: boolean }[];
    cli?: { binary: string; subcommands?: string[] }[];
    mcpTools?: { name: string; schemaRef?: string }[];
    renderSurfaces?: { kind: string; id?: string }[];
    hardwareDrivers?: { device: string; transport?: string; vendor?: string }[];
  };
  consumes?: {
    waveProducts?: { repo: string; endpoint?: string }[];
    thirdParty?: { service: string; licenseGated?: boolean }[];
    foundationFrameworks?: string[];
    hardware?: string[];
  };
  events?: {
    publishes?: { topic: string; transport?: string }[];
    subscribes?: { topic: string; transport?: string }[];
  };
  tags?: string[];
}

interface RegistryState {
  schemaVersion: string;
  generatedAt: string;
  repoCount: number;
  capabilities: Capabilities[];
}

const { values } = parseArgs({
  options: {
    in: { type: 'string', short: 'i', default: '/tmp/caps' },
    out: { type: 'string', short: 'o', default: 'frameworks/platform-registry' },
    // Optional extra baseline for generatedAt reuse, e.g. the standing
    // registry PR branch's state.json. Defaults to <out>/state.json only.
    prev: { type: 'string', short: 'p' },
  },
});

const IN_DIR = values.in ?? '/tmp/caps';
const OUT_DIR = values.out ?? 'frameworks/platform-registry';
const PREV_PATH = values.prev;

async function main(): Promise<void> {
  const files = await fs.readdir(IN_DIR);
  const capabilities: Capabilities[] = [];
  for (const f of files) {
    if (!f.endsWith('.json')) continue;
    const raw = await fs.readFile(join(IN_DIR, f), 'utf8');
    try {
      const parsed = JSON.parse(raw) as Capabilities;
      capabilities.push(parsed);
    } catch (err) {
      console.error(`skip ${f}: ${err instanceof Error ? err.message : err}`);
    }
  }
  capabilities.sort((a, b) => a.repo.localeCompare(b.repo));

  const state: RegistryState = {
    schemaVersion: '1',
    generatedAt: new Date().toISOString(),
    repoCount: capabilities.length,
    capabilities,
  };

  // Keep the committed artifact stable: if the only difference from a
  // previous state.json is the generatedAt stamp, reuse the old stamp so
  // runs with unchanged content produce no diff (and the aggregate
  // workflow's change-detect / create-pull-request steps stay quiet).
  // Baselines, first byte-match wins:
  //   1. --prev (e.g. the standing registry PR branch's copy), if given
  //   2. <out>/state.json (the base checkout's copy)
  const statePath = join(OUT_DIR, 'state.json');
  const baselines = [...new Set([PREV_PATH, statePath].filter((p): p is string => !!p))];
  for (const baseline of baselines) {
    let prevRaw: string;
    try {
      prevRaw = await fs.readFile(baseline, 'utf8');
    } catch {
      continue; // No baseline at this path — try the next one.
    }
    try {
      const prev = JSON.parse(prevRaw) as Partial<RegistryState>;
      if (typeof prev.generatedAt === 'string') {
        const candidate = `${JSON.stringify({ ...state, generatedAt: prev.generatedAt }, null, 2)}\n`;
        if (candidate === prevRaw) {
          state.generatedAt = prev.generatedAt;
          break;
        }
      }
    } catch {
      // Corrupt baseline — ignore and try the next one.
    }
  }

  await fs.writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`);
  await fs.writeFile(join(OUT_DIR, 'STATE.md'), renderMarkdown(state));
  console.log(`wrote state.json + STATE.md (${capabilities.length} repos)`);
}

function renderMarkdown(state: RegistryState): string {
  const lines: string[] = [];
  lines.push('# Platform State');
  lines.push('');
  lines.push(`> Content last changed ${state.generatedAt} (${state.repoCount} repos). The aggregator may have swept more recently without finding changes; see the workflow run summary for sweep liveness.`);
  lines.push('>');
  lines.push('> Do NOT hand-edit — modify each repo\'s `capabilities.json` and re-run the aggregator.');
  lines.push('');

  // Group by plane layer; null/non-plane goes last.
  const buckets = new Map<string, Capabilities[]>();
  for (const cap of state.capabilities) {
    const key = cap.planeLayer === null || cap.planeLayer === undefined
      ? 'non-plane'
      : `layer-${cap.planeLayer}`;
    const list = buckets.get(key) ?? [];
    list.push(cap);
    buckets.set(key, list);
  }

  const order = ['layer-0', 'layer-1', 'layer-2', 'layer-3', 'layer-4', 'non-plane'];
  const titles: Record<string, string> = {
    'layer-0': 'Layer 0 — Operator (apps + plugins running on operator hardware)',
    'layer-1': 'Layer 1 — Edge (WebRTC / SFU / gateway / signal-everywhere edges)',
    'layer-2': 'Layer 2 — Bridges (container-based protocol bridges)',
    'layer-3': 'Layer 3 — Local (agents + flash + offline-capable nodes)',
    'layer-4': 'Layer 4 — Hardware (designs, certified profiles, validation)',
    'non-plane': 'Non-plane (SDKs, marketing surfaces, agent tooling, governance)',
  };

  for (const key of order) {
    const items = buckets.get(key);
    if (!items || items.length === 0) continue;
    lines.push(`## ${titles[key]}`);
    lines.push('');
    lines.push('| Repo | Version | Lifecycle | Exposes (count) | Consumes WAVE | Tags |');
    lines.push('|---|---|---|---|---|---|');
    for (const cap of items) {
      const exposesCount =
        (cap.exposes?.apis?.length ?? 0) +
        (cap.exposes?.cli?.length ?? 0) +
        (cap.exposes?.mcpTools?.length ?? 0) +
        (cap.exposes?.renderSurfaces?.length ?? 0) +
        (cap.exposes?.hardwareDrivers?.length ?? 0);
      const consumesCount = cap.consumes?.waveProducts?.length ?? 0;
      const tags = (cap.tags ?? []).join(' · ') || '—';
      lines.push(
        `| [\`${cap.repo}\`](https://github.com/${cap.repo}) | ${cap.version} | ${cap.lifecycle} | ${exposesCount} | ${consumesCount} | ${tags} |`,
      );
    }
    lines.push('');
  }

  // Cross-references — who consumes whom.
  lines.push('## Cross-references');
  lines.push('');
  const reverse = new Map<string, string[]>();
  for (const cap of state.capabilities) {
    for (const consumed of cap.consumes?.waveProducts ?? []) {
      const list = reverse.get(consumed.repo) ?? [];
      list.push(cap.repo);
      reverse.set(consumed.repo, list);
    }
  }
  const reverseSorted = [...reverse.entries()].sort(([a], [b]) => a.localeCompare(b));
  if (reverseSorted.length === 0) {
    lines.push('_None registered yet — backfill in progress._');
  } else {
    lines.push('| Repo | Consumed by |');
    lines.push('|---|---|');
    for (const [target, consumers] of reverseSorted) {
      lines.push(`| \`${target}\` | ${consumers.map((r) => `\`${r}\``).join(', ')} |`);
    }
  }
  lines.push('');

  return lines.join('\n');
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
