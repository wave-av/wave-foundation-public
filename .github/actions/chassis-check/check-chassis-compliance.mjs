#!/usr/bin/env node
/**
 * check-chassis-compliance.mjs — gate that every *.wave.online product worker
 * (a) depends on @wave-av/spoke-chassis in its package.json, and
 * (b) serves a chassis-branded landing page at its root /.
 *
 * WHY THIS EXISTS
 * ---------------
 * Several product workers were scaffolded as standalone custom workers with no
 * @wave-av deps at all. Their public face was ad-hoc HTML while chassis spokes
 * served the full branded landing — inconsistent, and invisible to every other
 * check we had, because nothing fails when a worker simply does its own thing.
 * See every-product-host-on-chassis.md.
 *
 * CONTRACT
 * --------
 * --repo <path>      Check package.json at <path>/package.json for the dep.
 *                    Exit 0 = present; exit 1 = missing; exit 2 = usage error.
 * --landing <host>   Fetch https://<host>/ and probe chassis markers.
 *                    Exit 0 = pass; exit 1 = fail; exit 2 = usage error.
 *
 * Stable chassis markers (from packages/spoke-chassis/src/shell.ts):
 *   <link rel="manifest" href="/manifest.webmanifest">
 *   <script type="application/ld+json">
 *   <script src="/_wave/nav.js" defer></script>
 *   <main id="main" class="card">
 *
 * We require at least 2 of these 4 to pass — avoids false-positive on any
 * future per-marker change while still catching blank/bespoke pages.
 *
 * Node 22, stdlib only (no npm deps).
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createRequire } from "node:module";

// ─── CHASSIS DEP CHECK ────────────────────────────────────────────────────────

function checkRepo(repoPath) {
  const pkgPath = join(repoPath, "package.json");
  let pkg;
  try {
    pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  } catch (e) {
    console.error(`check-chassis-compliance: cannot read ${pkgPath}: ${e.message}`);
    return 1;
  }

  const deps = {
    ...(pkg.dependencies ?? {}),
    ...(pkg.devDependencies ?? {}),
    ...(pkg.peerDependencies ?? {}),
  };

  const CHASSIS = "@wave-av/spoke-chassis";
  if (CHASSIS in deps) {
    console.log(`check-chassis-compliance: ✓ ${CHASSIS} found in ${pkgPath}`);
    return 0;
  }

  console.error(
    `check-chassis-compliance: ✗ ${CHASSIS} is MISSING from ${pkgPath}\n` +
    `  Every *.wave.online product worker MUST depend on ${CHASSIS}.\n` +
    `  See rules/every-product-host-on-chassis.md.`
  );
  return 1;
}

// ─── LANDING PROBE ────────────────────────────────────────────────────────────

// All 4 chassis markers (from shell.ts output). We require ≥2 to pass.
const CHASSIS_MARKERS = [
  '<link rel="manifest"',
  '<script type="application/ld+json">',
  '<script src="/_wave/nav.js"',
  '<main id="main" class="card">',
];
const REQUIRED_MARKER_HITS = 2;

async function checkLanding(host) {
  // Basic host validation — must not contain a scheme or path.
  if (host.includes("://") || host.includes("/")) {
    console.error(
      `check-chassis-compliance: ✗ --landing expects a bare hostname (e.g. clips.wave.online), got: ${host}`
    );
    return 1;
  }

  const url = `https://${host}/`;
  console.log(`check-chassis-compliance: probing ${url} …`);

  let html;
  try {
    const res = await fetch(url, {
      redirect: "follow",
      headers: { "User-Agent": "wave-foundation/chassis-compliance-check" },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      console.error(
        `check-chassis-compliance: ✗ ${url} returned HTTP ${res.status} — expected 200.`
      );
      return 1;
    }
    // Read up to 64KB — chassis head fits well within this.
    const buf = await res.arrayBuffer();
    html = new TextDecoder().decode(buf.slice(0, 65536));
  } catch (e) {
    console.error(`check-chassis-compliance: ✗ fetch ${url} failed: ${e.message}`);
    return 1;
  }

  const hits = CHASSIS_MARKERS.filter((m) => html.includes(m));
  if (hits.length >= REQUIRED_MARKER_HITS) {
    console.log(
      `check-chassis-compliance: ✓ ${host}/ passes chassis check (${hits.length}/${CHASSIS_MARKERS.length} markers found)`
    );
    return 0;
  }

  const missing = CHASSIS_MARKERS.filter((m) => !html.includes(m));
  console.error(
    `check-chassis-compliance: ✗ ${host}/ is NOT serving the chassis landing.\n` +
    `  Found ${hits.length}/${CHASSIS_MARKERS.length} markers (need ≥${REQUIRED_MARKER_HITS}).\n` +
    `  Missing markers:\n${missing.map((m) => `    · ${m}`).join("\n")}\n` +
    `  Every *.wave.online product host MUST serve the @wave-av/spoke-chassis landing at /.\n` +
    `  See rules/every-product-host-on-chassis.md.`
  );
  return 1;
}

// ─── ENTRYPOINT ───────────────────────────────────────────────────────────────

function usage() {
  console.error(
    "Usage:\n" +
    "  check-chassis-compliance.mjs --repo <path>     Check package.json for @wave-av/spoke-chassis\n" +
    "  check-chassis-compliance.mjs --landing <host>  Probe https://<host>/ for chassis markers"
  );
  return 2;
}

const args = process.argv.slice(2);
const repoIdx = args.indexOf("--repo");
const landingIdx = args.indexOf("--landing");

if (repoIdx === -1 && landingIdx === -1) {
  process.exit(usage());
}

const tasks = [];

if (repoIdx !== -1) {
  const repoPath = args[repoIdx + 1];
  if (!repoPath) {
    console.error("check-chassis-compliance: --repo requires a path argument");
    process.exit(2);
  }
  tasks.push(Promise.resolve(checkRepo(repoPath)));
}

if (landingIdx !== -1) {
  const host = args[landingIdx + 1];
  if (!host) {
    console.error("check-chassis-compliance: --landing requires a hostname argument");
    process.exit(2);
  }
  tasks.push(checkLanding(host));
}

const results = await Promise.all(tasks);
const exitCode = results.some((r) => r !== 0) ? 1 : 0;
process.exit(exitCode);
