#!/usr/bin/env bash
# Cases are dispatched indirectly (`"case_$c" ...`) so each one can be re-run against the real script
# and against each mutant. shellcheck cannot see an indirect call and reports every case as dead
# code. This directive must sit BEFORE the first command to apply file-wide — after one, it binds
# only to the next command, which is how the first attempt at it silently did nothing.
# shellcheck disable=SC2329
#
# test-check-file-size.sh — self-test for frameworks/gates/scripts/check-file-size.sh.
#
# WHAT IT PINS (#965). That script is the pre-commit MIRROR of checks.yml's File-size gate, and a
# mirror's entire value is agreeing with the thing it mirrors. #939 fixed two real defects in it and
# neither had a test, so either could regress in silence:
#
#   1. THE SWALLOWED LISTER (#944 class). `git ls-files` failing used to print
#      "file-size: ✓ all code files <= 800 lines" and exit 0 — a gate that scanned NOTHING reporting
#      the same line it prints over a clean tree. Case C.
#   2. BASH 3.2 UNBOUND ARRAY. `"${files[@]}"` on an EMPTY array is an unbound-variable error under
#      `set -u` in bash 3.2 — the macOS system bash this pre-commit hook actually runs under, and
#      NOT the bash 5 on most developers' PATH. Case D runs under /bin/bash on purpose; run under
#      bash 5 it passes either way and proves nothing.
#
# Cases E/F/G pin the mirror's SCAN SET and SKIP SET behaviourally. #927 compares those lists
# statically, which catches a renamed glob but not a path-filter that stopped being applied — and
# the header of the script under test records that it was wrong in BOTH directions until 2026-07-29
# (a 900-line .sh passed locally and was blocked by CI; a 900-line dist/*.js was blocked locally and
# exempt in CI). That disagreement is the failure mode: developers learn to distrust the local hook.
#
# NOT PINNED HERE: the self-granted-exemption hole (#1003) — an allowlist entry added in the same
# commit as the file it excuses is still honoured by this gate. That is a known OPEN defect, and a
# drill must not enshrine current-but-wrong behaviour as expected. Case H asserts only that a
# PRE-EXISTING allowlist entry works. When #1003 lands, its case belongs in this file.
#
# Each case builds a throwaway git repo under mktemp and runs the REAL script inside it. Nothing is
# written into this repository.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/scripts/check-file-size.sh"
[ -f "$SCRIPT" ] || {
  echo "error: script not found at $SCRIPT" >&2
  exit 2
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0
skips=0
pass() { printf '  ok   %s\n' "$1"; }
fail() {
  printf '  FAIL %s\n' "$1"
  fails=$((fails + 1))
}
# A skip is COUNTED and NAMED. An unrunnable case that prints nothing is indistinguishable from one
# that ran and passed, which is the exact confusion the rest of this suite exists to prevent.
skip() {
  printf '  SKIP %s\n' "$1"
  skips=$((skips + 1))
}

# --- fixtures -------------------------------------------------------------------------------------
# `git init` in a fresh dir with the identity set locally: a machine with no global user.email would
# otherwise fail the commit and report a gate defect that is really a missing git config.
make_repo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email 'drill@wave.online'
  git -C "$d" config user.name 'drill'
  mkdir -p "$d/.github"
}

# Committing matters: the no-args path enumerates with `git ls-files`, which only sees TRACKED files.
# An untracked fixture would make every case look like "nothing to scan" and pass vacuously.
track() {
  local d="$1"
  shift
  git -C "$d" add -- "$@"
  git -C "$d" commit -q -m 'fixture' >/dev/null 2>&1
}

big_file() { python3 -c "import sys; open(sys.argv[1],'w').write('// line\n'*900)" "$1"; }
small_file() { printf 'console.log("ok");\n' >"$1"; }

# --- the runner under test ------------------------------------------------------------------------
# $1 = shell, $2 = script, $3 = cwd, rest = args. Captures stdout+stderr and the status together;
# the ✓ line is stdout and the ✗ lines are stderr, and a case that inspects only one of them can
# call a gate green while it is printing a violation.
run_gate() {
  local shell="$1" script="$2" cwd="$3"
  shift 3
  OUT="$(cd "$cwd" && "$shell" "$script" "$@" 2>&1)"
  RC=$?
  return 0
}

# --- mutants (discrimination) ----------------------------------------------------------------------
# Generated copies with ONE guard removed each, so we can show the relevant case FLIPS. A drill that
# has never been run against a broken version is a drill nobody has verified can fail.
mutate() {
  python3 - "$SCRIPT" "$2" "$1" <<'PY'
import sys
src, dst, which = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src, encoding='utf-8').read()
if which == 'array':
    # Restore the bare expansion that breaks on bash 3.2 with an empty array.
    old, new = 'for f in ${files[@]+"${files[@]}"}; do', 'for f in "${files[@]}"; do'
elif which == 'lister':
    # Restore the fail-OPEN enumerator: status discarded, so a failure reads as "found nothing".
    old = '''  if ! git ls-files -- "${SCAN_GLOBS[@]}" >"$list"; then
    echo "file-size: ✗ git ls-files FAILED — refusing to report a pass" >&2
    exit 1
  fi'''
    new = '  git ls-files -- "${SCAN_GLOBS[@]}" >"$list" 2>/dev/null || true'
else:
    sys.exit('unknown mutant %s' % which)
if old not in s:
    sys.exit('mutant %s: anchor not found — the script changed shape; update this drill' % which)
open(dst, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
}

MUT_ARRAY="$work/mutant-array.sh"
MUT_LISTER="$work/mutant-lister.sh"
if mutate array "$MUT_ARRAY" && mutate lister "$MUT_LISTER"; then
  pass "built both mutants from the real script (anchors still present)"
else
  fail "could not build mutants — anchors not found in $SCRIPT"
  echo "  -> the script under test changed shape; this drill is stale and cannot discriminate."
  exit 1
fi

# ===================================================================================================
# CASES
# ===================================================================================================

# --- A: control — a compliant tree passes ---------------------------------------------------------
case_A() {
  local d="$work/A-$1"
  make_repo "$d"
  small_file "$d/ok.ts"
  track "$d" ok.ts
  run_gate "$2" "$3" "$d"
  [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'all code files' && return 0
  return 1
}

# --- B: control — a 900-line file is flagged -------------------------------------------------------
case_B() {
  local d="$work/B-$1"
  make_repo "$d"
  big_file "$d/huge.ts"
  track "$d" huge.ts
  run_gate "$2" "$3" "$d"
  # exit 1 AND the ✗ line AND no ✓ line: "flagged" must not coexist with an all-clear.
  [ "$RC" -ne 0 ] &&
    printf '%s' "$OUT" | grep -qE 'huge\.ts has +900 lines' &&
    ! printf '%s' "$OUT" | grep -q 'all code files' && return 0
  return 1
}

# --- C: the swallowed lister must fail CLOSED ------------------------------------------------------
# Run with cwd outside any git repo, so `git ls-files` genuinely fails. The gate must refuse to
# report a pass rather than print ✓ over zero scanned files.
case_C() {
  local d="$work/C-$1"
  mkdir -p "$d" # deliberately NOT a git repo
  run_gate "$2" "$3" "$d"
  [ "$RC" -ne 0 ] && ! printf '%s' "$OUT" | grep -q 'all code files' && return 0
  return 1
}

# --- D: empty match set must not explode under bash 3.2 --------------------------------------------
# A tracked repo with NO files matching the scan set leaves the array empty. Under bash 3.2 the bare
# expansion raises "unbound variable"; the guarded one is silent.
case_D() {
  local d="$work/D-$1"
  make_repo "$d"
  printf '# readme\n' >"$d/README.md"
  track "$d" README.md
  run_gate "$2" "$3" "$d"
  [ "$RC" -eq 0 ] &&
    printf '%s' "$OUT" | grep -q 'all code files' &&
    ! printf '%s' "$OUT" | grep -qi 'unbound variable' && return 0
  return 1
}

# --- E: scan set — a 900-line .sh is in scope ------------------------------------------------------
# The direction that once let a file pass locally and get blocked by CI.
case_E() {
  local d="$work/E-$1"
  make_repo "$d"
  big_file "$d/big.sh"
  track "$d" big.sh
  run_gate "$2" "$3" "$d"
  # Padding-tolerant on purpose: BSD `wc` pads, GNU `wc` does not, and this drill runs on both.
  [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qE 'big\.sh has +900 lines' && return 0
  return 1
}

# --- F: skip set — a 900-line dist/*.js is exempt BY PATH -------------------------------------------
# The opposite direction of the same drift: blocked locally, exempt in CI.
case_F() {
  local d="$work/F-$1"
  make_repo "$d"
  mkdir -p "$d/dist"
  big_file "$d/dist/bundle.js"
  track "$d" dist/bundle.js
  run_gate "$2" "$3" "$d"
  [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'all code files' && return 0
  return 1
}

# --- G: the skip set applies to EXPLICIT ARGS too ---------------------------------------------------
# pre-commit hands the hook staged paths with no path filtering. If skip_path were applied only on
# the enumerated path, dist/*.js would fail locally and pass in CI — which is exactly what happened.
case_G() {
  local d="$work/G-$1"
  make_repo "$d"
  mkdir -p "$d/dist"
  big_file "$d/dist/bundle.js"
  track "$d" dist/bundle.js
  run_gate "$2" "$3" "$d" "dist/bundle.js"
  [ "$RC" -eq 0 ] && return 0
  return 1
}

# --- H: a PRE-EXISTING allowlist entry is honoured ---------------------------------------------------
# Committed in an EARLIER commit than the file it excuses, deliberately: see the #1003 note in the
# header — this case must not depend on the same-commit behaviour that is still broken.
case_H() {
  local d="$work/H-$1"
  make_repo "$d"
  printf 'huge.ts\n' >"$d/.github/.filesize-allowlist"
  track "$d" .github/.filesize-allowlist
  big_file "$d/huge.ts"
  track "$d" huge.ts
  run_gate "$2" "$3" "$d"
  [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'all code files' && return 0
  return 1
}

# --- I: FILE_SIZE_MAX overrides the cap --------------------------------------------------------------
case_I() {
  local d="$work/I-$1"
  make_repo "$d"
  big_file "$d/huge.ts"
  track "$d" huge.ts
  OUT="$(cd "$d" && FILE_SIZE_MAX=1000 "$2" "$3" 2>&1)"
  RC=$?
  [ "$RC" -eq 0 ] && return 0
  return 1
}

# ===================================================================================================
# RUN — the real script must pass everything.
# ===================================================================================================
echo "── the real gate (bash 5 on PATH, and /bin/bash $(/bin/bash -c 'echo $BASH_VERSION')) ──"
for c in A B C D E F G H I; do
  if "case_$c" "real" bash "$SCRIPT"; then pass "$c  (real gate)"; else fail "$c  (real gate)"; fi
done

# Case D needs a bash OLDER THAN 4.0. `"${arr[@]}"` on an empty array is an unbound-variable error
# under `set -u` in bash 3.2 and legal from 4.4 on, so the case only measures anything on the old
# shell — that is the whole point, since macOS pre-commit runs under /bin/bash 3.2.57.
#
# FOUND BY CI (#1004 shipped this hardcoded to /bin/bash). On macOS /bin/bash IS 3.2, so it passed
# locally; on the Linux runner /bin/bash is bash 5, where the mutant is legal and the discrimination
# check reported FAIL. The shell has to be DISCOVERED, and when no old bash exists the case must SKIP
# WITH A NAMED REASON — never silently pass, which is the same "0 tests looks like 0 failures" defect
# this whole suite exists to catch.
BASH32=""
for cand in /bin/bash /usr/bin/bash /bin/sh; do
  [ -x "$cand" ] || continue
  v=$("$cand" -c 'echo ${BASH_VERSINFO[0]:-0}' 2>/dev/null) || continue
  case "$v" in ''|*[!0-9]*) continue ;; esac
  [ "$v" -lt 4 ] && { BASH32="$cand"; break; }
done

if [ -n "$BASH32" ]; then
  if case_D "real32" "$BASH32" "$SCRIPT"; then
    pass "D  (real gate, $BASH32 $("$BASH32" -c 'echo $BASH_VERSION') — the shell pre-commit uses)"
  else
    fail "D  (real gate, $BASH32 — the shell pre-commit uses)"
  fi
else
  skip "D  (real gate, bash <4) — no bash older than 4.0 on this host; the empty-array error does
       not exist on bash 4.4+, so there is nothing here to measure. Runs on macOS (/bin/bash 3.2)."
fi

# ===================================================================================================
# DISCRIMINATION — each mutant must break its OWN case and leave the controls alone.
# ===================================================================================================
echo "── mutants (each case must FLIP for its own defect, and only for it) ──"

# mutant-array: bare "${files[@]}" — breaks ONLY under bash <4, ONLY with an empty array. Same shell
# discovery as case D, and the same rule: with no old bash there is no defect to reintroduce, so this
# SKIPS rather than reporting a pass or a failure. Reporting FAIL here (what shipped in #1004) is
# actively misleading — it says the drill is blind when in fact the regression cannot exist.
if [ -n "$BASH32" ]; then
  if case_D "mut32" "$BASH32" "$MUT_ARRAY"; then
    fail "mutant-array: case D still passed — the drill cannot see the bash <4 regression"
  else
    pass "mutant-array: case D fails (unguarded empty array under $BASH32)"
  fi
  for c in A B; do
    if "case_$c" "mutA-$c" "$BASH32" "$MUT_ARRAY"; then
      pass "mutant-array: control $c unaffected"
    else
      fail "mutant-array: control $c broke — the mutant is too broad to attribute case D"
    fi
  done
else
  skip "mutant-array (3 checks) — needs a bash older than 4.0; the defect it restores cannot occur
       on bash 4.4+, so there is nothing for the mutant to prove here."
fi

# mutant-lister: status discarded — a FAILING enumerator becomes "found nothing" and reports ✓.
if case_C "mutL" bash "$MUT_LISTER"; then
  fail "mutant-lister: case C still passed — the drill cannot see the fail-open lister"
else
  pass "mutant-lister: case C fails (swallowed git ls-files reports a pass)"
fi
for c in A B; do
  if "case_$c" "mutL-$c" bash "$MUT_LISTER"; then
    pass "mutant-lister: control $c unaffected"
  else
    fail "mutant-lister: control $c broke — the mutant is too broad to attribute case C"
  fi
done

echo
if [ "$fails" -eq 0 ]; then
  if [ "$skips" -gt 0 ]; then
    # Named in the verdict line, not just mid-run. A green that silently covered less than a previous
    # green is how coverage erodes without anyone deciding to erode it.
    echo "check-file-size drill: ALL CASES PASS ($skips skipped — see SKIP lines for why)"
  else
    echo "check-file-size drill: ALL CASES PASS"
  fi
  exit 0
fi
echo "check-file-size drill: $fails FAILURE(S)"
exit 1
