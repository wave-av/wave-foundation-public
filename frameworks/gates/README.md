# Gates — the left-shift gate registry

A **gate** is a rule that runs both locally (a git-stage hook) and in CI, off **one shared script**,
so a failure is caught *as code is written* — not discovered after a push or PR. This directory is the
system that keeps the two in sync.

## The problem it solves

Each gate used to be wired by hand in three places — `.pre-commit-config.yaml`, the reusable
`checks.yml`, and the scaffolder template. Three places drift. A rule that's stricter locally than in
CI (or vice-versa) is worse than no rule: it teaches people to ignore it.

## How it works

- **`registry.yaml`** — every gate declared once: its id, the shared script, the git stage
  (`commit-msg` / `pre-commit`), file globs, and which CI job runs it.
- **`emit.py`** — turns the registry into config and, crucially, verifies config hasn't drifted:
  - `emit.py --precommit` — print the generated `repo: local` hook block.
  - `emit.py --check` — **fail if `.pre-commit-config.yaml` doesn't match the registry.** Wired into
    `self-check.yml` (`gate-registry-drift` job), so the registry is provably authoritative.
  - `emit.py --list` — human summary.
- **`scripts/`** — the gate scripts that don't live elsewhere (`check-file-size.sh`,
  `check-model-strings.sh`). Title + Claude-API-shape gates reuse their existing canonical scripts
  (`frameworks/hooks/`, `frameworks/claude-api/`).

## Registered gates

| id | stage | script | also in CI |
|----|-------|--------|------------|
| `conventional-title` | commit-msg | `hooks/validate-conventional-title.sh` | `semantic-pr.yml` parity step |
| `claude-api-shape` | pre-commit | `claude-api/lint-request-shape.sh` | `checks.yml` + `self-check.yml` |
| `file-size` | pre-commit | `gates/scripts/check-file-size.sh` | `checks.yml` + `self-check.yml` |
| `model-string` | pre-commit | `gates/scripts/check-model-strings.sh` | (pre-commit-only for now) |

Registry-ready TODOs (native pre-push, separate install path): `branch-ref-safety`, `prod-token-guard`.

## Add a gate

1. Write the shared script (idempotent, reads file args, exits non-zero on violation, stderr messages).
2. Append an entry to `registry.yaml`.
3. `python3 emit.py --precommit` and reconcile `.pre-commit-config.yaml` (or hand-add the hook to match).
4. Commit. `self-check.yml`'s drift job verifies parity.

## Propagation to spokes

`consume.sh` vendors `frameworks/` (this dir included) read-only into every spoke's `.foundation/`.
Spokes point their `.pre-commit-config.yaml` hooks at `.foundation/frameworks/gates/scripts/…`; the
scaffolder template wires the title + shape gates for new repos out of the box. The reusable
`checks.yml` runs the vendored scripts in CI everywhere — same script, no drift.

## Diagram

The dogfood gate lifecycle is drawn in [`docs/diagrams/state/gate-lifecycle.md`](../../docs/diagrams/state/gate-lifecycle.md) (catalog: `docs/diagrams/README.md`).
