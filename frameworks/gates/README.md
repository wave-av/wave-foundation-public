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
  - `emit.py --list` — human-readable summary.
- **`scripts/`** — the gate scripts that don't live elsewhere (`check-file-size.sh`,
  `check-model-strings.sh`). Title + Claude-API-shape gates reuse their existing canonical scripts
  (`frameworks/hooks/`, `frameworks/claude-api/`).

## Registered gates

**Do not hand-maintain this list — print it:** `python3 frameworks/gates/emit.py --list`. A table
transcribed by hand is a fourth place to drift, in the document that exists to argue against drift.
This one had: it listed four gates while the registry declared seven, omitting `secret-scan` — the
gate that had itself been inert in CI for months (#926/#928).

| id | stage | script | ci job |
|----|-------|--------|--------|
| `conventional-title` | commit-msg | `hooks/validate-conventional-title.sh` | `semantic-pr` (parity step) |
| `claude-api-shape` | pre-commit | `claude-api/lint-request-shape.sh` | `claude-api-shape` |
| `claude-api-cache` | pre-commit | `claude-api/lint-cache-control.sh` | `claude-api-cache` |
| `secret-scan` | pre-commit | `gates/scripts/secret-scan.sh` | `secret-scan` |
| `file-size` | pre-commit | `gates/scripts/check-file-size.sh` | `file-size` |
| `model-string` | pre-commit | `gates/scripts/check-model-strings.sh` | `claude-api-shape` |
| `model-thinking-capability` | pre-commit | `gates/scripts/check-model-thinking-capability.sh` | `claude-api-shape` |

Registry-ready TODOs (native pre-push, separate install path): `branch-ref-safety`, `prod-token-guard`.

## Run the gates locally, on CI's architecture (#929)

Pre-commit runs the gates on *your* machine. That is not the same computation as CI: this Mac is
ARM64 and resolves `grep` to **ugrep**, while CI is x86_64 running **GNU grep** — a difference that
produced opposite verdicts on the same pipeline during #926, and hid a live fail-open until the
pipeline was re-run in a container. A green computed in the wrong environment is not evidence.

```bash
bash frameworks/gates/scripts/run-local.sh              # every runnable gate, ~7s warm
bash frameworks/gates/scripts/run-local.sh secret-scan  # just one
bash frameworks/gates/scripts/verify-receipt.sh         # does a receipt vouch for HEAD?
```

`run-local.sh` rsyncs the tree to an x86_64 Docker host and runs the **same script files** CI runs —
it does not reimplement them, which is the defect #926 documents. Exit codes are disjoint on purpose:
**0** all passed · **1** a gate failed (your code) · **2** infrastructure failed. An unreachable host
must never read as clean.

It writes a receipt to `~/.claude/state/waveci-receipts/`. `verify-receipt.sh` is the reader, and
every ambiguous case is UNVERIFIED — no receipt, unparseable JSON, a dirty tree, a partial gate set,
or a gate whose script has changed since. It is an **integrity aid, not authentication**: the receipt
is unsigned and user-writable. It answers *"did I actually run this"*, not *"is this developer
honest"*, and no merge path may treat it otherwise.

### Install the pre-push hook

Deliberately manual — checking out a repo must never install a hook that reaches out to a remote host.

```bash
ln -sf ../../frameworks/gates/scripts/pre-push.sh .git/hooks/pre-push
```

A **gate** failure blocks the push. An **infrastructure** failure does not: a laptop with no route to
the CI host must still be able to push, or everyone learns `--no-verify` by reflex and the block that
matters stops working too. The consequence is simply that no receipt exists, so `verify-receipt.sh`
reports UNVERIFIED — the push is not the enforcement point, the receipt is.

Env: `WAVECI_HOST` (**required** — `user@host`), `WAVECI_HOST_FILE` (default
`~/.config/waveci/host`, a one-line fallback so you needn't export it every shell), `WAVECI_IMAGE`
(digest-pinned), `WAVECI_RECEIPTS`, `WAVECI_SKIP=1` to skip (which writes **no** receipt — an escape
hatch that emitted a passing receipt would be a forgery vector).

**The runner address is not in this repo, on purpose.** `frameworks/` is mirrored publicly and the
runner is reached over Tailscale, so its CGNAT address is internal infrastructure —
`scripts/sync-public.sh` holds back any publishable file containing one. It used to be hardcoded
here and in `run-local.sh`, which left both files permanently un-mirrorable and `open-core-audit`
(a **required** check) red on `main`. Allowlisting them would have turned the audit green *while
publishing the address*, which is the opposite of what the gate is for.

An unconfigured host is **infrastructure** (exit 2), not a gate failure — so pre-push allows the
push, loudly, and writes no receipt.

### Install the merge-path check

The push is not the enforcement point; the receipt is. This is where the receipt is read.

```bash
ln -sf ../../frameworks/gates/scripts/verify-merge-receipt.sh .git/hooks/prepare-commit-msg
```

A merge whose incoming commit has no receipt — or a stale one, written before a gate script changed —
is blocked. An ordinary commit is untouched and silent.

**`prepare-commit-msg`, not `pre-merge-commit`.** Measured on git 2.50.1: at `pre-merge-commit` time
`MERGE_HEAD` does not exist yet, so a hook there cannot name the commit being merged and fails open on
every merge. `commit-msg` would work but is owned by the pre-commit framework
(`default_install_hook_types`), and installing there would clobber the conventional-title gate.

**What it does not cover, plainly:** a **fast-forward** merge creates no commit, so no commit hook runs
— use `--no-ff`. And `gh pr merge` is **server-side**, which is where this repo's PRs actually land; a
local hook cannot see it.

Escape hatch: `WAVECI_MERGE_ALLOW_UNVERIFIED=1`, which announces itself. `git merge --no-verify` does
**not** reach this slot — git's `--no-verify` covers `pre-merge-commit` and `commit-msg` only. A
blocked merge is left in progress by git; `git merge --abort` clears it.

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
