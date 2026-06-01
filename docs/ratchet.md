# The changed-files lint ratchet

Stops **new** lint debt from entering the repo without forcing a bulk-fix of **existing** debt.

## How it works

Each linter's every current finding is snapshotted as a normalized **signature** into a committed
baseline. On a PR, the linter runs and only the PR-touched files are compared against the baseline —
the gate fails **only on a signature not in the baseline**. Existing debt is paid down
fix-as-we-go; new debt can't sneak in.

Signatures drop `:line:col:` (and any dynamic numbers) so they survive edits elsewhere in a file —
a finding is identified by `path + rule + message`, not its line.

## Active gates

| Language | Tool | Script | Baseline | Status |
|----------|------|--------|----------|--------|
| Shell | `shellcheck --severity=warning` | `scripts/shell-check-changed.sh` | `.shellcheck-baseline.txt` | BLOCKING |
| Python | `ruff check` (pinned) | `scripts/python-check-changed.sh` | `.python-baseline.txt` | BLOCKING |
| C / C++ | `cppcheck --enable=warning,portability` | `scripts/cpp-check-changed.sh` | `.cppcheck-baseline.txt` | DORMANT* |
| Rust | `cargo clippy -W clippy::all` | `scripts/rust-check-changed.sh` | `.clippy-baseline.txt` | DORMANT* |

\*DORMANT = wired, runs on every PR, but a clean no-op here because wave-foundation has **zero native
files** (the baselines are empty by design — same as the SQL/TS "ready recipe" precedent below). The
job activates the instant native code appears. It is NOT a faked green: it skips only when no
C/C++/Rust file changed, and FAILS CLOSED on a missing tool or (for Rust) a `*.rs` with no crate.
See the **Native languages (C/C++/Rust)** section below.

**Skipped** (per "skip any language the repo doesn't use"):

- **SQL** — no `.sql` files. Recipe ready in `RATCHET-5` if ever added (`sqlfluff`, signature
  `PATH: CODE [rule]`).
- **TypeScript** — no *canonical* TS (the only `.ts` is faithful `staging/` harvest). The TS recipe
  exists but is **inactive**: it would use `tsgo` (`@typescript/native-preview`) + a standalone
  `tsconfig.tsgo.json` if canonical TS is ever maintained.

## Usage

Every script shares one contract:

```bash
scripts/<lang>-check-changed.sh                    # gate changed files vs the baseline (default)
scripts/<lang>-check-changed.sh --update-baseline  # regenerate the baseline over ALL tracked files
scripts/<lang>-check-changed.sh --base <ref>        # diff base (default origin/master)
scripts/<lang>-check-changed.sh --ci               # terse output
```

Exit codes: **0** = no new findings · **1** = NEW findings · **2** = setup error (tool/baseline
missing — **fail closed**, never fail-open).

### Regenerate a baseline (after fixing debt, or adding a rule)

```bash
scripts/shell-check-changed.sh  --update-baseline   # → .shellcheck-baseline.txt
scripts/python-check-changed.sh --update-baseline   # → .python-baseline.txt
scripts/cpp-check-changed.sh    --update-baseline   # → .cppcheck-baseline.txt  (native repos)
scripts/rust-check-changed.sh   --update-baseline   # → .clippy-baseline.txt    (native repos)
git add .shellcheck-baseline.txt .python-baseline.txt && git commit -m "chore: refresh ratchet baseline"
```

Commit the baselines — they're diffable, so reviewers watch the debt shrink.

## Toolchain

Each script resolves its tool via a fallback chain so it works locally and in CI:
`binary on PATH → uvx <tool>@<pinned> → uv tool run <tool>@<pinned>`. Versions are **pinned**
(ruff `0.15.14`) so baselines stay stable. `UV_CACHE_DIR` is set to a writable path (uv's default
cache can be unwritable in locked-down runners). In CI: `astral-sh/setup-uv` (SHA-pinned) provides
`uvx` for ruff; `shellcheck` is preinstalled on `ubuntu-latest`.

## Rollout: observed, then enforced

`ratchet.yml` ran **warn-only** (`|| true`) from 2026-05-27, then flipped to **BLOCKING** on
2026-05-28 after 5 consecutive PRs (#43-#48) passed with 0 false-positives — the spec's observation
window satisfied. `shell ratchet` and `python ratchet` are now required-status checks; a NEW finding
in a PR-touched file blocks the merge.

Never leave a `|| true` on a required check — a faked-green required check is silent error-masking
that defeats the ratchet.

## Native languages (C/C++/Rust)

Native repos (`wave-transports` and the per-protocol native bindings — see
[polyrepo-topology](../rules/polyrepo-topology.md)) ship C/C++/Rust addons. Those languages need the
ratchet from day one, so the recipe is added **here** (the governance root) and inherited via the
shared workflow — not reinvented per repo.

Same contract as shell/python: `path + rule + message` signature (line/col dropped), empty-baseline
default, fail-closed on a missing tool, identical four flags.

- **C / C++ — `cppcheck`.** Chosen as the primary because it does whole-file static analysis with **no
  compile database**, so the gate works the moment the first `.c`/`.cpp`/header lands — no build
  wiring required. Template `{file}:{line}:{column}: {severity}: {message} [{id}]` matches the
  shellcheck gcc shape, so the same `normalize` sed yields the signature. Honors
  `// cppcheck-suppress` inline (the C/C++ analogue of `# pragma: allowlist`).
- **Rust — `cargo clippy`.** Clippy must **compile** the crate, so it runs per Cargo workspace
  (one per `Cargo.toml` dir). With no crate present the gate is a clean no-op over zero `*.rs`;
  it FAILS CLOSED if a `*.rs` changes with no `Cargo.toml` (a crate-less `.rs` clippy can't build).
  Signatures come from `--message-format=json` so they're stable across edits.

### Rollout (when native code lands)

These two jobs are wired but **dormant** in wave-foundation (no native files). Do NOT add them to
required checks here — there's nothing to observe. Instead, in the FIRST native repo
(`wave-transports`): consume this workflow, populate the baselines once
(`scripts/cpp-check-changed.sh --update-baseline`, `scripts/rust-check-changed.sh --update-baseline`,
commit both), run **warn-only for 5 consecutive PRs**, then flip to required — exactly the rollout the
shell/python ratchets followed (§"Rollout: observed, then enforced"). Never leave a `|| true` on a
required native check once flipped.

### Explicit TODOs (need a real native repo to complete — not stubbed)

These are deliberately NOT wired with fake/green placeholders; they require a buildable native repo to
exercise honestly:

- **TODO(clang-tidy oracle):** cppcheck is the fast per-PR gate; `clang-tidy` is the deeper oracle but
  needs `compile_commands.json` from a real CMake/Bazel build. Wire it as a **scheduled** job (per
  §Redundancy) in `wave-transports` once that repo produces a compile database. A new script
  `scripts/clang-tidy-changed.sh` would mirror `cpp-check-changed.sh` against the compile DB.
- **TODO(toolchain pinning):** pin the exact `cppcheck` apt version and the Rust toolchain
  (`rust-toolchain.toml` + clippy version) in the consuming native repo so baseline signatures stay
  stable across runner-image bumps — the same pinning shellcheck-py/ruff use here. Cannot pin
  meaningfully until a real build defines the supported toolchain.
- **TODO(per-crate scoping):** the Rust script lints every workspace on each run; once
  `wave-transports` has multiple crates, scope clippy to only the workspaces whose files changed (cheap
  with cargo metadata) to keep CI fast. Premature to optimize against a non-existent layout.

## Redundancy

If a language has a slow authoritative checker (e.g. `tsc` vs the fast `tsgo`, or `clang-tidy` vs the
fast `cppcheck`), run the slow oracle as a **scheduled** job (nightly / on trunk-promotion), not
per-PR. Divergence between the fast gate and the slow oracle is a bug to file, not a silent miss.
