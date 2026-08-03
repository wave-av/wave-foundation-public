#!/usr/bin/env bash
# test-pre-push.sh — self-test for frameworks/gates/scripts/pre-push.sh.
#
# This file exists because the hook shipped as a FAIL-OPEN and the reason was the test, not the code.
# The hook was verified by invoking the script directly — never through the relative symlink the
# install line actually creates. Through that symlink it could not find run-local.sh, exited 127,
# was classified as INFRASTRUCTURE, and allowed every push with a message blaming the network while
# the gates had not run at all.
#
# So the load-bearing case here is INSTALLED-SHAPE, not the code path: a fake repo, a real relative
# symlink at .git/hooks/pre-push, and git's own cwd (the repo root). A hook tested any other way is
# not a tested hook.
#
# run-local.sh is STUBBED so the exit-code policy can be exercised without a container or a network.
# The policy is the thing under test; run-local's own behaviour is covered where it lives.
#
# Usage:  bash frameworks/gates/test-pre-push.sh
# Exit:   0 = every case behaved as specified · 1 = at least one regressed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/scripts/pre-push.sh"
[ -f "$HOOK" ] || { echo "error: $HOOK not found" >&2; exit 1; }

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# new_repo <name> <run-local-exit|absent> — a throwaway repo with the hook installed exactly as the
# install line installs it: a RELATIVE symlink under .git/hooks.
new_repo() {
  local d="$work/$1" stub="$2"
  mkdir -p "$d/frameworks/gates/scripts"
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t )
  cp "$HOOK" "$d/frameworks/gates/scripts/pre-push.sh"
  if [ "$stub" != "absent" ]; then
    printf '#!/usr/bin/env bash\necho "stub run-local (exit %s)"\nexit %s\n' "$stub" "$stub" \
      > "$d/frameworks/gates/scripts/run-local.sh"
  fi
  ln -sf ../../frameworks/gates/scripts/pre-push.sh "$d/.git/hooks/pre-push"
  printf '%s' "$d"
}

# expect <case> <want_exit> <want_substring|-> <repo> [env...]
expect() {
  local name="$1" want="$2" text="$3" d="$4"; shift 4
  local out rc
  # cwd = repo root and invocation via .git/hooks/pre-push — exactly how git runs it.
  out="$(cd "$d" && echo "" | env "$@" bash .git/hooks/pre-push 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    fail "$name — exit $rc, want $want"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"; return
  fi
  if [ "$text" != "-" ] && ! printf '%s' "$out" | grep -qF "$text"; then
    fail "$name — exit correct, but never says '$text'"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"; return
  fi
  pass "$name"
}

echo "== installed shape: a relative symlink, invoked from the repo root =="

# THE REGRESSION. Before the fix this printed "could not reach the CI host" and exited 0 — a push
# allowed, gates never run, blamed on the network.
expect "A  gates pass                    -> allow" 0 "gates passed" "$(new_repo a 0)"

# The case the whole hook exists for.
expect "B  a GATE failed                 -> BLOCK" 1 "BLOCKED" "$(new_repo b 1)"

# Deliberately NOT a block: a laptop with no route to the CI host must still be able to push, or
# everyone learns --no-verify by reflex and case B stops working too. No receipt is the consequence.
expect "C  INFRASTRUCTURE failed         -> allow, loudly" 0 "could not reach the CI host" "$(new_repo c 2)"

# A missing runner is a BROKEN INSTALL, not an unreachable host. Routing it to the allow-with-warning
# branch is exactly what hid the fail-open, so it must block and say so.
expect "D  run-local.sh missing          -> BLOCK as misinstalled" 1 "misinstalled" "$(new_repo d absent)"

echo "== escape hatch =="

# Skipping must leave no receipt — an escape hatch that emitted a passing receipt would be a forgery
# vector. Here we only assert it does not run the gates and does not block.
expect "E  WAVECI_SKIP=1                 -> skip, no receipt" 0 "no receipt written" "$(new_repo e 1)" WAVECI_SKIP=1

echo
if [ "$fails" -eq 0 ]; then
  echo "pre-push self-test: all cases pass"; exit 0
fi
echo "pre-push self-test: $fails case(s) FAILED"; exit 1
