#!/usr/bin/env node
// Drill for four frameworks/ gates (#944 rank 7):
//   frameworks/claude-api/lint-cache-control.sh    — vendored into spoke repos
//   frameworks/claude-api/lint-request-shape.sh    — vendored into spoke repos
//   frameworks/gates/scripts/check-model-strings.sh — pre-commit + CI
//   frameworks/repo-governance/governance-audit.sh  — a NETWORK lister
//
// The first three share a shape the earlier ranks did not have:
//
//     files=()
//     if [ "$#" -gt 0 ]; then files=("$@")
//     elif git rev-parse --git-dir >/dev/null 2>&1; then
//       while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
//     fi
//
// so there are TWO fail-open paths, not one. The swallowed `git ls-files` status is the #944 defect;
// the `elif` is a second one — outside a git repo the enumeration is skipped entirely and the lint
// prints its ✓ line, which reads as "no violations" and means "no input". Cases (b) cover that.
//
// governance-audit.sh is the #948 shape again (network lister; `gh` exits 0 on a 200 carrying []),
// so it needs an EMPTINESS guard as well as a status guard.
//
// Negative control: FW_DIR=<a dir holding origin/main's copies>.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..");
// Each entry maps a script to where it lives, so the negative control can point FW_DIR at a flat
// directory of origin/main copies without the harness caring about the real tree layout.
const FW_DIR = process.env.FW_DIR ? join(REPO, process.env.FW_DIR) : null;
const src = (relPath) => (FW_DIR ? join(FW_DIR, relPath.split("/").pop()) : join(REPO, relPath));

const CACHE = "frameworks/claude-api/lint-cache-control.sh";
const SHAPE = "frameworks/claude-api/lint-request-shape.sh";
const MODEL = "frameworks/gates/scripts/check-model-strings.sh";
const AUDIT = "frameworks/repo-governance/governance-audit.sh";

const realGit = execFileSync("sh", ["-c", "command -v git"]).toString().trim();

/** A git repo with the script copied to ./gate.sh and some tracked content. */
function fixture(scriptRel, files = { "src/a.py": "x = 1\n" }, { init = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "fw-drill-"));
  for (const [p, body] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, p)), { recursive: true });
    writeFileSync(join(dir, p), body);
  }
  execFileSync("cp", [src(scriptRel), join(dir, "gate.sh")]);
  if (init) {
    const g = (...a) => execFileSync("git", ["-C", dir, ...a], { stdio: "pipe" });
    execFileSync("git", ["init", "-q", "-b", "main", dir]);
    g("config", "gc.auto", "0"); // a background gc racing rmSync would decide the verdict
    g("config", "user.email", "drill@example.com");
    g("config", "user.name", "drill");
    g("add", "-A");
    g("commit", "-qm", "fixture");
  }
  return dir;
}

/** A PATH stub that fails ONE subcommand of `git` or `gh`, inside an otherwise valid repo. */
function stub(dir, cmd, failing, { emptyOk = false } = {}) {
  const bin = join(dir, ".stub");
  mkdirSync(bin, { recursive: true });
  const real = cmd === "git" ? realGit : "";
  const body = emptyOk
    ? `#!/bin/sh\nexit 0\n` // succeeds, prints nothing — the "200 carrying []" case
    : `#!/bin/sh\nfor a in "$@"; do [ "$a" = ${failing} ] && { echo "simulated ${failing} failure" >&2; exit ${cmd === "gh" ? 1 : 128}; }; done\n${real ? `exec ${real} "$@"` : "exit 0"}\n`;
  writeFileSync(join(bin, cmd), body, { mode: 0o755 });
  return bin;
}

function run(dir, { pathPrefix = "", args = [] } = {}) {
  try {
    const stdout = execFileSync("bash", ["gate.sh", ...args], {
      cwd: dir,
      env: { ...process.env, PATH: pathPrefix ? `${pathPrefix}:${process.env.PATH}` : process.env.PATH },
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { status: 0, stdout, stderr: "" };
  } catch (e) {
    return { status: e.status, stdout: e.stdout?.toString() ?? "", stderr: e.stderr?.toString() ?? "" };
  }
}

const cleanup = (dir) => {
  try {
    rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 50 });
  } catch {
    /* teardown must never decide the verdict */
  }
};

// [script, the ✓ string it must not print when it scanned nothing]
const TREE_SCANNERS = [
  [CACHE, "cache-control-lint: ✓"],
  [SHAPE, "claude-api-lint: ✓"],
  [MODEL, "model-string: ✓"],
];

for (const [scriptRel, okString] of TREE_SCANNERS) {
  const name = scriptRel.split("/").pop();

  test(`(a/${name}) a failed enumeration is blocked, not a pass`, () => {
    const dir = fixture(scriptRel);
    try {
      const r = run(dir, { pathPrefix: stub(dir, "git", "ls-files") });
      assert.equal(r.status, 2, `expected exit 2, got ${r.status}\n${r.stdout}${r.stderr}`);
      assert.ok(!r.stdout.includes(okString), `printed its pass line anyway:\n${r.stdout}`);
    } finally {
      cleanup(dir);
    }
  });

  test(`(b/${name}) running OUTSIDE a git repo with no args is an error, not a silent pass`, () => {
    // The second fail-open, independent of #944's: with no repo the `elif` skipped enumeration
    // entirely, files stayed empty, and the lint printed ✓ over zero files.
    const dir = fixture(scriptRel, { "src/a.py": "x = 1\n" }, { init: false });
    try {
      const r = run(dir);
      assert.equal(r.status, 2, `expected exit 2, got ${r.status}\n${r.stdout}${r.stderr}`);
      assert.ok(!r.stdout.includes(okString), `printed its pass line anyway:\n${r.stdout}`);
    } finally {
      cleanup(dir);
    }
  });

  test(`(c/${name}) a clean tree still PASSES — fail-closed must not become always-fail`, () => {
    const dir = fixture(scriptRel);
    try {
      const r = run(dir);
      assert.equal(r.status, 0, `expected exit 0, got ${r.status}\n${r.stdout}${r.stderr}`);
      assert.ok(r.stdout.includes(okString), r.stdout + r.stderr);
    } finally {
      cleanup(dir);
    }
  });

  test(`(d/${name}) explicit file args still work — arg mode must not require a repo`, () => {
    // pre-commit passes staged paths; that path must be unaffected by the enumeration guard.
    const dir = fixture(scriptRel, { "src/a.py": "x = 1\n" }, { init: false });
    try {
      const r = run(dir, { args: ["src/a.py"] });
      assert.equal(r.status, 0, `expected exit 0, got ${r.status}\n${r.stdout}${r.stderr}`);
    } finally {
      cleanup(dir);
    }
  });
}

test(`(e/check-model-strings.sh) a real date-suffixed model ID is still caught`, () => {
  // Can-it-fire. A guard that only ever refuses is not a gate.
  const dir = fixture(MODEL, { "src/m.json": '{"model":"claude-sonnet-4-6-20251114"}\n' }); // claude-api-lint: ignore (deliberate fixture: the assertion below is that the gate CATCHES this)
  try {
    const r = run(dir);
    assert.equal(r.status, 1, `expected exit 1, got ${r.status}\n${r.stdout}${r.stderr}`);
    assert.match(r.stderr, /date-suffixed model ID/);
  } finally {
    cleanup(dir);
  }
});

test(`(f/governance-audit.sh) a failed gh listing is a blocked audit, not "no public P0 gaps"`, () => {
  const dir = fixture(AUDIT, { "README.md": "x\n" });
  try {
    const r = run(dir, { pathPrefix: stub(dir, "gh", "list") });
    assert.equal(r.status, 2, `expected exit 2, got ${r.status}\n${r.stdout}${r.stderr}`);
    assert.ok(!r.stdout.includes("no public P0 gaps"), `claimed a clean audit anyway:\n${r.stdout}`);
  } finally {
    cleanup(dir);
  }
});

test(`(g/governance-audit.sh) an EMPTY gh listing refuses — exit 0 is not proof it enumerated`, () => {
  // #948's lesson, re-applied: `gh` exits 0 on a 200 carrying [], and a token lacking org read
  // scope returns an empty list rather than an error. A status check alone would still pass here.
  const dir = fixture(AUDIT, { "README.md": "x\n" });
  try {
    const r = run(dir, { pathPrefix: stub(dir, "gh", "", { emptyOk: true }) });
    assert.equal(r.status, 2, `expected exit 2, got ${r.status}\n${r.stdout}${r.stderr}`);
    assert.match(r.stderr, /came back EMPTY/);
  } finally {
    cleanup(dir);
  }
});
