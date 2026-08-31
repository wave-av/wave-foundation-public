#!/usr/bin/env bash
# pre-push — run the gates in the container before a push, and leave a receipt. (#929 scope 4.)
#
# Install (deliberately NOT automatic — checking out a repo must never install a hook that reaches
# out to a remote host):
#
#     ln -sf ../../frameworks/gates/scripts/pre-push.sh .git/hooks/pre-push
#
# ── The exit-code policy, which is the only interesting decision here ────────────────────────────
#
# run-local.sh already separates "your code failed" from "the infrastructure failed", and this hook
# is where that distinction earns its keep:
#
#   run-local 0  gates passed          -> allow the push. A receipt now exists for this commit.
#   run-local 1  a GATE failed         -> BLOCK the push. This is your code; fix it.
#   run-local 2  INFRASTRUCTURE failed -> ALLOW the push, loudly, and leave NO receipt.
#
# Blocking on 2 would be the intuitive "fail-closed" reading and it is the wrong call. A laptop with
# no route to the CI host would be unable to push at all, and within a day everyone would be pushing
# with `--no-verify` reflexively — which also disables the block for case 1, the one that matters.
# An escape hatch people use by habit protects nothing.
#
# The resolution is that THE PUSH IS NOT THE ENFORCEMENT POINT; THE RECEIPT IS. When the host is
# unreachable no receipt is written, so `verify-receipt.sh` reports UNVERIFIED for that commit at the
# merge path — which is where fail-closed belongs, and where it cannot be shrugged past. The hook is
# a fast local signal; the receipt is the durable claim.
#
# That merge path is `verify-merge-receipt.sh`, installed as a prepare-commit-msg hook (#966). Until
# it existed the sentence above described an enforcement point that did not exist — the fail-open
# here was justified by coverage nobody had built. Two limits it does NOT cover, so this policy is
# read with them in view: a FAST-FORWARD merge runs no commit hook at all, and `gh pr merge` is
# server-side, which is where this repo's PRs actually land.
#
# Exit: 0 = push proceeds · 1 = push blocked (a gate failed)
set -uo pipefail

# Resolved from the repo root, NOT from $BASH_SOURCE. git invokes hooks with cwd at the top level,
# and `.git/hooks/pre-push` is a RELATIVE symlink — so `readlink` returns `../../frameworks/...`,
# which is relative to `.git/hooks/`, while a `cd` of it happens from the repo root and lands two
# levels ABOVE the repo. That is how the first version of this hook shipped as a fail-open: it never
# found run-local.sh, exited 127, was classified as INFRASTRUCTURE, and allowed every push with a
# message blaming the network while the gates had not run at all. It was only ever tested by
# invoking the script directly — never through the symlink the install line actually creates.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "pre-push: BLOCKED — not inside a git repo" >&2; exit 1; }
HERE="$ROOT/frameworks/gates/scripts"

# A missing runner is a BROKEN INSTALL, not an unreachable host, and it must never take the
# allow-with-a-warning path — that is precisely the branch that hid the bug above. Blocking is right
# here: a hook that cannot find its runner is not a hook, and a silent allow is how it stays broken.
[ -f "$HERE/run-local.sh" ] || {
  echo "pre-push: BLOCKED — $HERE/run-local.sh not found. The hook is misinstalled; the gates did" >&2
  echo "          NOT run. Reinstall: ln -sf ../../frameworks/gates/scripts/pre-push.sh .git/hooks/pre-push" >&2
  exit 1; }

# git feeds the hook `<local ref> <local sha> <remote ref> <remote sha>` on stdin. It is drained and
# discarded on purpose: the gates run against the working tree, not against a named ref, and ref
# names are attacker-influenceable strings that have no business reaching a command line.
cat >/dev/null 2>&1 || true

if [ "${WAVECI_SKIP:-}" = "1" ]; then
  # Skipping must leave NO receipt. An escape hatch that emitted a passing receipt would be a
  # forgery vector wearing the label "convenience".
  echo "pre-push: WAVECI_SKIP=1 — gates skipped, no receipt written (this commit will read UNVERIFIED)"
  exit 0
fi

echo "pre-push: running gates in the container (warm ~7s)…"
bash "$HERE/run-local.sh"
rc=$?

case "$rc" in
  0)
    echo "pre-push: gates passed — receipt written"
    exit 0 ;;
  1)
    echo "pre-push: BLOCKED — a gate failed. Fix it, or push with --no-verify and accept that this" >&2
    echo "          commit will read UNVERIFIED at the merge path." >&2
    exit 1 ;;
  *)
    # Anything that is not a clean pass or a clean gate failure is treated as infrastructure. `2` is
    # what run-local.sh emits deliberately; a 126/127/130 (not executable, not found, interrupted) is
    # also not evidence about your code, and must not be reported as though it were.
    echo "pre-push: WARNING — could not reach the CI host (run-local exit $rc)." >&2
    echo "          Push allowed, but NO receipt was written: this commit reads UNVERIFIED." >&2
    echo "          Re-run later: bash frameworks/gates/scripts/run-local.sh" >&2
    exit 0 ;;
esac
