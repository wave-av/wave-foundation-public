#!/usr/bin/env bash
# test-verify-merge-receipt.sh — self-test for scripts/verify-merge-receipt.sh. (#966.)
#
# EVERY CASE INSTALLS THE SYMLINK AND RUNS A REAL `git merge`. Invoking the hook script directly is
# exactly how pre-push.sh's relative-path fail-open escaped its own test: it worked when called by
# path and was broken when git called it through `.git/hooks/`, which is the only way it is ever
# actually called. A hook drill that does not go through the symlink measures something nobody runs.
#
# Fixtures are throwaway repos under mktemp -d with WAVECI_RECEIPTS pointed into the same temp dir,
# so the real receipt store is never read or written.
#
# Usage:  bash frameworks/gates/test-verify-merge-receipt.sh
# Exit:   0 = every case behaved as specified · 1 = at least one regressed.
#
# SC1090: mutant hooks are generated into a temp dir at run time, so their paths cannot be constant —
# that is what a mutant is. This directive must precede the FIRST COMMAND to apply file-wide; placed
# after one it binds only to the next command.
# shellcheck disable=SC1090
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
HOOK="$HERE/scripts/verify-merge-receipt.sh"
[ -f "$HOOK" ] || { echo "error: $HOOK not found" >&2; exit 1; }
# shellcheck source=frameworks/gates/scripts/lib/waveci-common.sh
. "$HERE/scripts/lib/waveci-common.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export WAVECI_RECEIPTS="$work/receipts"
mkdir -p "$WAVECI_RECEIPTS"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
show() { printf '       %s\n' "$(printf '%s' "$1" | head -3)"; }

# ── fixture ──────────────────────────────────────────────────────────────────────────────────────
# A real repo carrying the real scripts the hook drives, plus a synthetic registry and synthetic
# gates. Synthetic so a change to the live gate set cannot make this suite pass or fail for an
# unrelated reason; real scripts because the point is that the hook drives the ACTUAL verifier.
#
# `beta`'s id is deliberately not its filename — that mismatch is what left run-local.sh's own
# default invocation broken from the day it shipped, so anything that reconstructs a script path
# instead of reading it from the registry trips here.
new_repo() { # new_repo <dir> [--no-verifier]
  local d="$1" want_verifier=1
  [ "${2:-}" = "--no-verifier" ] && want_verifier=0
  mkdir -p "$d/frameworks/gates/scripts/lib"
  cp "$HERE/scripts/lib/waveci-common.sh" "$d/frameworks/gates/scripts/lib/"
  [ "$want_verifier" -eq 1 ] && cp "$HERE/scripts/verify-receipt.sh" "$d/frameworks/gates/scripts/"
  cat >"$d/frameworks/gates/registry.yaml" <<'YAML'
gates:
  - id: alpha
    script: frameworks/gates/scripts/alpha.sh
  - id: beta
    script: frameworks/gates/scripts/check-beta.sh
YAML
  echo 'echo alpha ok' >"$d/frameworks/gates/scripts/alpha.sh"
  echo 'echo beta ok'  >"$d/frameworks/gates/scripts/check-beta.sh"
  (
    cd "$d" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    git config commit.gpgsign false
    # UNIQUE origin per fixture, because the receipt store is shared and keyed {repo}-{sha}.json.
    # The fixture trees and messages are byte-identical, so two repos created within the same
    # SECOND mint identical commit SHAs — and with one shared repo name, a case then reads a
    # receipt some earlier case wrote (or poisoned). Measured, not hypothetical: on a fast runner
    # M3 collided with case C's tip and was blocked by C's corrupted receipt ("gate has CHANGED")
    # instead of its own missing one. The dir basename namespaces every case's receipts instead.
    git remote add origin "git@example.com:wave-av/fixture-$(basename "$d").git"
    git add -- frameworks
    git commit -qm base
  ) >/dev/null 2>&1
}

install_hook() { # install_hook <repo> [hook-source] — through the symlink, always.
  local d="$1" src="${2:-$HOOK}"
  mkdir -p "$d/.git/hooks"
  ln -sf "$src" "$d/.git/hooks/prepare-commit-msg"
  chmod +x "$src" 2>/dev/null || true
}

# A valid receipt, built through the WRITER's own functions (#967) so this suite cannot drift from
# the format run-local.sh actually emits.
write_receipt() { # write_receipt <repo> <sha>
  local d="$1" sha="$2" repo rows=() gid script
  repo=$(cd "$d" && waveci_repo_name "$d")
  while IFS=$'\t' read -r gid script; do
    [ -n "$gid" ] || continue
    rows+=("$(waveci_gate_row "$gid" "$(cd "$d" && git show "$sha:$script" | shasum -a 256 | cut -d' ' -f1)" 0 "$(printf '' | shasum -a 256 | cut -d' ' -f1)")")
  done < <(cd "$d" && waveci_registry_gates)
  waveci_receipt_json "$repo" "$sha" false clean h i t ${rows[@]+"${rows[@]}"} \
    >"$WAVECI_RECEIPTS/${repo}-${sha}.json"
}

feature() { # feature <repo> <branch> — one commit on a branch, left checked out on main
  local d="$1" b="$2"
  (
    cd "$d" || exit 1
    git checkout -q -b "$b" main
    echo "$b" >"$b.txt"
    git add -- "$b.txt"
    git commit -qm "$b"
    git checkout -q main
  ) >/dev/null 2>&1
}

merge_out() { # merge_out <repo> <branch> [extra git args] -> output + trailing `rc=<n>`
  local d="$1" b="$2"; shift 2
  ( cd "$d" && git merge --no-ff -m "merge $b" "$@" "$b" 2>&1; printf '\nrc=%s' "$?" )
}
head_of() { ( cd "$1" && git rev-parse main ); }
# A blocked merge is left IN PROGRESS by git — deliberately, so it cannot silently evaporate. Every
# case that blocks must clear it, and the fact that this helper is needed is itself the behaviour.
abort_merge() { ( cd "$1" && git merge --abort ) >/dev/null 2>&1; }

echo "== A/B. the core verdict: no receipt blocks, a receipt allows =="

R="$work/a"; new_repo "$R"; install_hook "$R"; feature "$R" feat
TIP=$(cd "$R" && git rev-parse feat)
BEFORE=$(head_of "$R")

out=$(merge_out "$R" feat)
if printf '%s' "$out" | grep -qF "no receipt for" && ! printf '%s' "$out" | grep -q 'rc=0'; then
  pass "A  no receipt -> merge BLOCKED, and it says why"
else fail "A  no receipt -> merge BLOCKED, and it says why"; show "$out"; fi
if [ "$(head_of "$R")" = "$BEFORE" ]; then pass "A2 main is unmoved after a blocked merge"
else fail "A2 main is unmoved after a blocked merge"; fi
abort_merge "$R"

write_receipt "$R" "$TIP"
out=$(merge_out "$R" feat)
if printf '%s' "$out" | grep -q 'rc=0' && printf '%s' "$out" | grep -qF "VERIFIED $TIP"; then
  pass "B  valid receipt -> merge ALLOWED"
else fail "B  valid receipt -> merge ALLOWED"; show "$out"; fi
if [ "$(head_of "$R")" != "$BEFORE" ]; then pass "B2 the merge commit exists"
else fail "B2 the merge commit exists"; fi

echo "== C. a receipt that no longer describes the code it vouches for =="

# The stale-pass case: the receipt is well-formed and complete, but a gate script has changed since
# it was written, so it certifies logic that is not what would run now. Same shape as a receipt that
# predates an edit to the gate.
R="$work/c"; new_repo "$R"; install_hook "$R"; feature "$R" feat
TIP=$(cd "$R" && git rev-parse feat)
write_receipt "$R" "$TIP"
REPO=$(cd "$R" && waveci_repo_name "$R")
python3 - "$WAVECI_RECEIPTS/${REPO}-${TIP}.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["gates"][0]["gate_file_sha256"] = "0" * 64
json.dump(d, open(p, "w"))
PY
out=$(merge_out "$R" feat)
if printf '%s' "$out" | grep -qF "has CHANGED since this receipt"; then
  pass "C  a gate changed since the receipt -> BLOCKED"
else fail "C  a gate changed since the receipt -> BLOCKED"; show "$out"; fi
abort_merge "$R"

echo "== D. the escape hatch — ours, because git's does not reach this slot =="

# MEASURED, not assumed: `git merge --no-verify` covers pre-merge-commit and commit-msg, and
# prepare-commit-msg always runs. D1 pins that, because it is the reason this hook carries an env
# hatch at all — and if a future git changes it, the justification in the header stops being true.
R="$work/d"; new_repo "$R"; install_hook "$R"; feature "$R" feat
BEFORE=$(head_of "$R")
out=$(merge_out "$R" feat --no-verify)
if [ "$(head_of "$R")" = "$BEFORE" ]; then
  pass "D1 git merge --no-verify does NOT reach prepare-commit-msg (still blocked)"
else fail "D1 git merge --no-verify does NOT reach prepare-commit-msg — git changed; revisit the header"; fi
abort_merge "$R"

out=$( cd "$R" && WAVECI_MERGE_ALLOW_UNVERIFIED=1 git merge --no-ff -m m feat 2>&1; printf '\nrc=%s' "$?" )
if printf '%s' "$out" | grep -q 'rc=0' && printf '%s' "$out" | grep -qF "OVERRIDDEN" \
   && [ "$(head_of "$R")" != "$BEFORE" ]; then
  pass "D2 WAVECI_MERGE_ALLOW_UNVERIFIED=1 merges, and SAYS so"
else fail "D2 WAVECI_MERGE_ALLOW_UNVERIFIED=1 merges, and SAYS so"; show "$out"; fi

echo "== E. a broken install must BLOCK, never allow-with-a-warning =="

# The failure mode that shipped pre-push.sh as a fail-open. A hook that cannot find what it checks
# with has not checked anything, and reporting that as a warning is how it stays broken for months.
R="$work/e"; new_repo "$R" --no-verifier; install_hook "$R"; feature "$R" feat
BEFORE=$(head_of "$R")
out=$(merge_out "$R" feat)
if printf '%s' "$out" | grep -qF "hook is misinstalled" && [ "$(head_of "$R")" = "$BEFORE" ]; then
  pass "E  missing verify-receipt.sh -> BLOCKED as a misinstall"
else fail "E  missing verify-receipt.sh -> BLOCKED as a misinstall"; show "$out"; fi
abort_merge "$R"

echo "== F. the holes and the silent paths, pinned so they stay VISIBLE =="

# F1 — a FAST-FORWARD merge creates no commit, so NO commit hook runs and an unverified commit merges
# silently. This asserts the hole rather than fixing it: a limitation that is measured is one the
# next reader can see, and the alternative is someone assuming coverage that is not there. `--no-ff`
# is the answer, and it is what every other case here uses.
R="$work/f"; new_repo "$R"; install_hook "$R"; feature "$R" feat
BEFORE=$(head_of "$R")
out=$( cd "$R" && git merge --ff-only feat 2>&1; printf '\nrc=%s' "$?" )
if printf '%s' "$out" | grep -q 'rc=0' && [ "$(head_of "$R")" != "$BEFORE" ] \
   && ! printf '%s' "$out" | grep -qF "no receipt for"; then
  pass "F1 fast-forward bypasses every commit hook (documented hole, not a fix)"
else fail "F1 fast-forward bypasses every commit hook — behaviour changed, update the docs"; show "$out"; fi

# F2 — this hook runs on EVERY commit, so an ordinary commit outside a merge must be a silent exit 0.
# A merge gate that made normal committing noisy or slow would be uninstalled within a day.
R="$work/f2"; new_repo "$R"; install_hook "$R"
out=$( cd "$R" && echo z >z.txt && git add -- z.txt && git commit -m plain 2>&1; printf '\nrc=%s' "$?" )
if printf '%s' "$out" | grep -q 'rc=0' && ! printf '%s' "$out" | grep -qF "verify-merge-receipt"; then
  pass "F2 an ordinary commit is untouched and silent"
else fail "F2 an ordinary commit is untouched and silent"; show "$out"; fi

echo "== G/H. every incoming commit is checked, and MERGE_HEAD is not trusted blindly =="

# G — an octopus merge has several MERGE_HEAD lines and EVERY one is being merged. Verifying only the
# first would let a second, unverified branch in under cover of the first's receipt. main is given
# its own commit first, so git cannot quietly fast-forward to `one` and turn this into a different
# test than the one it claims to be.
R="$work/g"; new_repo "$R"; install_hook "$R"; feature "$R" one; feature "$R" two
( cd "$R" && echo diverge >d.txt && git add -- d.txt && git commit -qm diverge ) >/dev/null 2>&1
write_receipt "$R" "$(cd "$R" && git rev-parse one)"
BEFORE=$(head_of "$R")
out=$( cd "$R" && git merge --no-ff -m octopus one two 2>&1; printf '\nrc=%s' "$?" )
if printf '%s' "$out" | grep -qF "no receipt for" && [ "$(head_of "$R")" = "$BEFORE" ]; then
  pass "G  octopus: one verified + one not -> BLOCKED"
else fail "G  octopus: one verified + one not -> BLOCKED"; show "$out"; fi
abort_merge "$R"

# H — the sha reaches `git show "$sha:$script"` inside the verifier. MERGE_HEAD is written by git and
# should always be clean, but a validator applied only to inputs already believed safe is a validator
# that is not applied. Driven by writing MERGE_HEAD directly, because git will not produce this state
# on its own — which is the point. The payload would CREATE A FILE if it were ever evaluated, so the
# assertion is the file's absence: grepping the output for the payload text cannot work, because the
# hook echoes the offending line back in its own error message.
R="$work/h"; new_repo "$R"; install_hook "$R"
printf 'x; touch %s/PWNED\n' "$work" > "$R/.git/MERGE_HEAD"
out=$( cd "$R" && bash .git/hooks/prepare-commit-msg .git/MERGE_MSG merge 2>&1; printf '\nrc=%s' "$?" )
if printf '%s' "$out" | grep -qF "not a 40-hex commit" && [ ! -e "$work/PWNED" ]; then
  pass "H  a non-hex MERGE_HEAD line is refused, and never evaluated"
else fail "H  a non-hex MERGE_HEAD line is refused, and never evaluated"; show "$out"; fi
rm -f "$R/.git/MERGE_HEAD" "$work/PWNED"

# H2 — an EMPTY MERGE_HEAD verifies zero commits, and "checked nothing" must never read as
# "everything passed". git never writes this state, so like H it is driven by writing the file
# directly — the only way it appears is something going wrong, which is why it must fail closed.
R="$work/h2"; new_repo "$R"; install_hook "$R"
: > "$R/.git/MERGE_HEAD"
out=$( cd "$R" && bash .git/hooks/prepare-commit-msg .git/MERGE_MSG merge 2>&1; printf '\nrc=%s' "$?" )
if printf '%s' "$out" | grep -qF "names no incoming commit" && ! printf '%s' "$out" | grep -q 'rc=0'; then
  pass "H2 an empty MERGE_HEAD is BLOCKED, not waved through"
else fail "H2 an empty MERGE_HEAD is BLOCKED, not waved through"; show "$out"; fi
rm -f "$R/.git/MERGE_HEAD"

echo "== M. mutants — a drill never run against a broken version is one nobody has verified =="

# M1 — THE BUG THIS FILE ACTUALLY CAUGHT. The first draft installed at `pre-merge-commit`, which is
# the slot the hook obviously wants. Measured on git 2.50.1: at pre-merge-commit time the git dir has
# AUTO_MERGE and ORIG_HEAD but NO MERGE_HEAD, so the hook cannot name what is being merged, takes its
# "nothing incoming" exit 0, and waves every merge through. The mutant is the wrong slot, and case A
# must be what catches it.
R="$work/m1"; new_repo "$R"; feature "$R" feat
mkdir -p "$R/.git/hooks"; ln -sf "$HOOK" "$R/.git/hooks/pre-merge-commit"
BEFORE=$(head_of "$R")
out=$(merge_out "$R" feat)
if [ "$(head_of "$R")" != "$BEFORE" ]; then
  pass "M1 MUTANT (pre-merge-commit slot) sees no MERGE_HEAD and fails OPEN — A discriminates"
else fail "M1 MUTANT (pre-merge-commit slot) fails open — it blocked, so the slot argument is stale"; fi

# M2 — treat a missing verifier as a warning and allow. The fail-open shape, restored; case E must be
# what catches it.
MUT2="$work/mutant-failopen.sh"
python3 - "$HOOK" "$MUT2" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
old = '''          ln -sf ../../frameworks/gates/scripts/verify-merge-receipt.sh .git/hooks/prepare-commit-msg" >&2
    exit 1; }'''
new = '''          ln -sf ../../frameworks/gates/scripts/verify-merge-receipt.sh .git/hooks/prepare-commit-msg" >&2
    exit 0; }'''
assert src.count(old) == 1, f"mutant target matched {src.count(old)} times, want 1"
pathlib.Path(sys.argv[2]).write_text(src.replace(old, new))
PY
chmod +x "$MUT2"
R="$work/m2"; new_repo "$R" --no-verifier; install_hook "$R" "$MUT2"; feature "$R" feat
BEFORE=$(head_of "$R")
merge_out "$R" feat >/dev/null
if [ "$(head_of "$R")" != "$BEFORE" ]; then
  pass "M2 MUTANT (misinstall allows) lets the merge through — E discriminates"
else fail "M2 MUTANT (misinstall allows) lets the merge through — it still blocked, so E proves nothing"; fi
abort_merge "$R"

# M3 — CONTROL. M2's edit touches only the misinstall branch, so a correctly-installed repo must
# still block on a missing receipt. If every case flipped, the mutant would be too broad to attribute
# anything to.
R="$work/m3"; new_repo "$R"; install_hook "$R" "$MUT2"; feature "$R" feat
BEFORE=$(head_of "$R")
out=$(merge_out "$R" feat)
if printf '%s' "$out" | grep -qF "no receipt for" && [ "$(head_of "$R")" = "$BEFORE" ]; then
  pass "M3 CONTROL: M2 does not disturb the normal verdict"
else fail "M3 CONTROL: M2 does not disturb the normal verdict — the mutant is too broad"; show "$out"; fi
abort_merge "$R"

cd "$REPO_ROOT" || exit 1
echo
if [ "$fails" -eq 0 ]; then
  echo "test-verify-merge-receipt: PASS — the local merge path fail-closes, and its holes are pinned"
  exit 0
fi
echo "test-verify-merge-receipt: FAIL — $fails case(s) regressed" >&2
exit 1
