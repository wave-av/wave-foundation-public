#!/usr/bin/env bash
# verify-merge-receipt — refuse to complete a merge whose incoming commit has no local-CI receipt.
# (#966.) Installed as a `prepare-commit-msg` hook; see the slot argument below, which is the whole
# interesting part of this file.
#
# Install (deliberately NOT automatic, same posture as pre-push.sh — checking out a repo must never
# install a hook that starts making judgements):
#
#     ln -sf ../../frameworks/gates/scripts/verify-merge-receipt.sh .git/hooks/prepare-commit-msg
#
# ── Why this exists ──────────────────────────────────────────────────────────────────────────────
#
# pre-push.sh ALLOWS a push when the CI host is unreachable, and argued for that from a check that
# did not exist:
#
#   > THE PUSH IS NOT THE ENFORCEMENT POINT; THE RECEIPT IS. When the host is unreachable no receipt
#   > is written, so `verify-receipt.sh` reports UNVERIFIED for that commit at the merge path.
#
# The argument is right, and so is the fail-open it justifies: a laptop with no route to the host
# must still be able to push, or everyone learns `--no-verify` by reflex and the block that MATTERS
# stops working too. But nothing called verify-receipt.sh, so the second half was designed, not
# wired — an unreachable runner meant no receipt, no push block, and no merge-path check either. A
# comment describing an enforcement point that does not exist is its own defect, because the next
# reader assumes the coverage is there. This is that enforcement point.
#
# ── Why prepare-commit-msg, which looks like the wrong slot ──────────────────────────────────────
#
# `pre-merge-commit` is the hook this obviously wants to be, and it CANNOT WORK. Measured on git
# 2.50.1: at pre-merge-commit time the git dir contains AUTO_MERGE (a tree) and ORIG_HEAD, and
# **MERGE_HEAD does not exist yet** — so the hook has no way to name the commit being merged. A
# first draft of this file used that slot, found no MERGE_HEAD, and exited 0 on every merge: a
# silent fail-open of exactly the kind #966 is about. The drill caught it; nothing else would have.
#
#   hook                  MERGE_HEAD visible?   can block?
#   pre-merge-commit      NO                    yes  (but has nothing to check)
#   prepare-commit-msg    YES                   yes
#   commit-msg            YES                   yes  (slot taken — see below)
#   post-merge            YES                   no   (too late by definition)
#
# `commit-msg` would also work, and it is NOT available: `.pre-commit-config.yaml` sets
# `default_install_hook_types: [pre-commit, commit-msg]`, so the pre-commit framework owns that file
# and installing here would silently clobber the conventional-title gate. `prepare-commit-msg` is
# unclaimed in this repo.
#
# git passes ($1 message file, $2 source, $3 sha). All three are ignored on purpose: the source
# argument is "merge" only for some paths into a merge, and MERGE_HEAD is the authoritative signal.
#
# ── What this does NOT cover, stated here rather than discovered later ───────────────────────────
#
# 1. `gh pr merge` and the web merge button are SERVER-SIDE. A local hook cannot see them, and that
#    is this repo's normal merge path. This closes the LOCAL merge path only.
# 2. A FAST-FORWARD merge creates no commit, so no commit hook runs at all. `git merge --no-ff` does.
#    Pinned as a drill case so the hole stays measured and visible instead of assumed closed.
# 3. The receipt is unsigned and lives in a directory the local user can write. This is an INTEGRITY
#    AID — "did I actually run the gates over this commit" — never authentication. It does not
#    answer "is this developer telling the truth" and must never be described as if it did.
#
# ── The escape hatch, and why it has to be ours ──────────────────────────────────────────────────
#
# `git merge --no-verify` does NOT reach this hook — measured, not assumed: git's --no-verify covers
# pre-merge-commit and commit-msg, and prepare-commit-msg always runs. So a hook here with no hatch
# would be unbypassable, which sounds like strength and is not: an unbypassable local check gets
# uninstalled the first time it is wrong, and then it protects nothing.
#
#     WAVECI_MERGE_ALLOW_UNVERIFIED=1 git merge --no-ff <branch>
#
# It is loud, it names itself in the output, and — unlike pre-push's WAVECI_SKIP — it cannot forge
# anything: it suppresses a VERDICT, it does not write a receipt.
#
# NOTE ON A BLOCKED MERGE: git leaves the merge IN PROGRESS ("Not committing merge; use 'git commit'
# to complete the merge"). MERGE_HEAD stays on disk, so the next `git commit` is still that merge and
# is still checked. `git merge --abort` clears it. That stickiness is deliberate — a blocked merge
# that silently evaporated would be indistinguishable from one that never started.
#
# Exit: 0 = the commit proceeds · 1 = blocked (an incoming commit is UNVERIFIED)
set -uo pipefail

# Resolved from the repo root, NOT from $BASH_SOURCE. git invokes hooks with cwd at the top level,
# and `.git/hooks/prepare-commit-msg` is a RELATIVE symlink — so `readlink` returns
# `../../frameworks/...`, which is relative to `.git/hooks/`, while a `cd` of it happens from the
# repo root and lands two levels ABOVE the repo. That is exactly how the first version of pre-push.sh
# shipped as a fail-open: it never found its runner, exited 127, was classified as INFRASTRUCTURE,
# and allowed every push with a message blaming the network while the gates had not run at all. It
# was only ever tested by invoking the script directly — never through the symlink the install line
# creates. Every case in the drill therefore installs the symlink.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "verify-merge-receipt: BLOCKED — not inside a git repo" >&2; exit 1; }
GIT_DIR_PATH="$(git rev-parse --git-dir 2>/dev/null)" || {
  echo "verify-merge-receipt: BLOCKED — cannot resolve the git dir" >&2; exit 1; }

# Not a merge => nothing incoming => nothing to say. This hook runs on EVERY commit, so the ordinary
# path must be a fast, silent exit 0. This is not a fail-open: no claim is being made.
MERGE_HEAD="$GIT_DIR_PATH/MERGE_HEAD"
[ -f "$MERGE_HEAD" ] || exit 0
# A MERGE_HEAD that exists but cannot be read is NOT "not a merge" — it is a merge this hook cannot
# see into, and treating it as the silent path above would be a fail-open. Same posture as the
# misinstall block below: a hook that cannot read its input has not checked anything.
[ -r "$MERGE_HEAD" ] || {
  echo "verify-merge-receipt: BLOCKED — $MERGE_HEAD exists but cannot be read; NOTHING was verified" >&2
  exit 1; }

VERIFY="$ROOT/frameworks/gates/scripts/verify-receipt.sh"
LIB="$ROOT/frameworks/gates/scripts/lib/waveci-common.sh"

# A missing verifier is a BROKEN INSTALL, not a missing receipt, and it must never take an
# allow-with-a-warning path — that is precisely the branch that hid the pre-push bug above. Blocking
# is right: a hook that cannot find what it checks with has not checked anything, and a silent allow
# is how it stays broken for months.
for f in "$VERIFY" "$LIB"; do
  [ -f "$f" ] || {
    echo "verify-merge-receipt: BLOCKED — $f not found. The hook is misinstalled; NOTHING was" >&2
    echo "          verified. Reinstall:" >&2
    echo "          ln -sf ../../frameworks/gates/scripts/verify-merge-receipt.sh .git/hooks/prepare-commit-msg" >&2
    exit 1; }
done
# shellcheck source=frameworks/gates/scripts/lib/waveci-common.sh
. "$LIB"

blocked=0
saw_head=0
# One sha per line. An octopus merge has several, and every one of them is being merged, so every one
# is checked — verifying only the first would let a second branch in under cover of the first's
# receipt.
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  saw_head=1
  # Validated before use: it reaches `git show "$sha:$script"` inside the verifier. MERGE_HEAD is
  # written by git and should always be clean, but a validator applied only to inputs already
  # believed safe is a validator that is not applied.
  waveci_sha_ok "$sha" || {
    echo "verify-merge-receipt: BLOCKED — MERGE_HEAD contains a line that is not a 40-hex commit" >&2
    blocked=1; continue; }

  if out=$(bash "$VERIFY" "$sha" 2>&1); then
    printf '%s\n' "$out"
  else
    # The verifier names its own reason, and it is a better message than any paraphrase. Print it,
    # then say what to do.
    printf '%s\n' "$out" >&2
    blocked=1
  fi
done < "$MERGE_HEAD"

# An EMPTY MERGE_HEAD means the loop verified zero commits, and "checked nothing" must never read as
# "everything passed". git never writes this state — which is exactly why it has to be handled: the
# only way it appears is something going wrong.
[ "$saw_head" -eq 1 ] || {
  echo "verify-merge-receipt: BLOCKED — MERGE_HEAD names no incoming commit; NOTHING was verified" >&2
  blocked=1; }

[ "$blocked" -eq 0 ] && exit 0

if [ "${WAVECI_MERGE_ALLOW_UNVERIFIED:-}" = "1" ]; then
  # Announced, never silent. An override nobody can see in the terminal is an override nobody
  # reviews — and this one leaves no trace anywhere else, because it writes nothing.
  echo "verify-merge-receipt: OVERRIDDEN — WAVECI_MERGE_ALLOW_UNVERIFIED=1. Merging an UNVERIFIED" >&2
  echo "          commit. No receipt was written and none will be; this commit still reads" >&2
  echo "          UNVERIFIED to anything that asks later." >&2
  exit 0
fi

echo "verify-merge-receipt: BLOCKED — an incoming commit is UNVERIFIED." >&2
echo "          Run the gates over it:  bash frameworks/gates/scripts/run-local.sh" >&2
echo "          Abandon the merge:      git merge --abort" >&2
echo "          Complete anyway (loud): WAVECI_MERGE_ALLOW_UNVERIFIED=1 git commit" >&2
echo "          (This reads a LOCAL, unsigned receipt. It proves the gates ran, not who ran them.)" >&2
exit 1
