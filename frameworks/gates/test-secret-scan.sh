#!/usr/bin/env bash
# test-secret-scan.sh — self-test for frameworks/gates/scripts/secret-scan.sh.
#
# The gate this covers was, until #928, INERT: a single blank line in .github/.secret-allowlist made
# `grep -vFf` discard every finding, so the scanner reported clean against a tree containing a live
# credential shape. Nothing caught it because the gate had no test — which is the actual lesson. A
# control with no test is a control whose failure mode is "silence".
#
# Every case builds a throwaway tree under a mktemp dir and runs the REAL script against it. Nothing
# is written into the repo, and no case depends on the repo's own allowlist.
#
# Cases A-D pin #928's behaviour (detect · clean · fail-closed on a MISSING allowlist · pragma
# bypass). Cases E-L pin #932: a MALFORMED allowlist is a loud gate failure, never a passing scan.
#
# Usage:  bash frameworks/gates/test-secret-scan.sh
# Exit:   0 = every case behaved as specified · 1 = at least one case regressed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/scripts/secret-scan.sh"
[ -f "$GATE" ] || { echo "error: $GATE not found" >&2; exit 1; }

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# The canary is assembled at runtime rather than written literally, so this test file itself never
# contains a credential-shaped string — otherwise the gate would flag its own test suite.
canary="AKIA$(printf 'ABCDEFGHIJKLMNOP')"

# new_tree <name> — a fresh scan root containing one file with the canary in it.
new_tree() {
  local d="$work/$1"
  mkdir -p "$d/.github" "$d/src"
  printf 'const key = "%s";\n' "$canary" > "$d/src/config.js"
  printf '%s' "$d"
}

# expect <case> <want_exit> <want_substring|-> <tree>
# Asserts the gate's exit code, and that its output names the reason. `-` skips the text assertion.
#
# The substring check is a bash [[ ... == *"$want_text"* ]] match, NOT `printf | grep -qF`: under
# pipefail, `grep -q` exits on first match and closes the pipe, printf can then die with EPIPE, and
# the pipeline "fails" on output that DOES contain the text — a race that flaked in CI.
expect() {
  local name="$1" want_exit="$2" want_text="$3" tree="$4" out rc
  out="$(cd "$tree" && bash "$GATE" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want_exit" ]; then
    fail "$name — exit $rc, want $want_exit"
    printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
    return
  fi
  if [ "$want_text" != "-" ] && [[ "$out" != *"$want_text"* ]]; then
    fail "$name — exit $rc correct, but output never says '$want_text'"
    printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
    return
  fi
  pass "$name"
}

echo "== #928 matrix — the gate detects, and fails closed =="

# A — canary present, well-formed allowlist that does NOT cover it: detected.
t="$(new_tree a)"
printf '# a real exception\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
expect "A  canary + non-covering allowlist -> detected" 1 "do not commit credentials" "$t"

# B — no canary: clean. Guards against a validator so strict it fails every tree.
t="$(new_tree b)"; rm -f "$t/src/config.js"; printf 'hello\n' > "$t/src/config.js"
printf '# a real exception\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
expect "B  clean tree                      -> clean" 0 "secret-scan clean" "$t"

# C — allowlist ABSENT. #926's fail-open: grep errored, `|| true` ate it, every tree passed.
t="$(new_tree c)"
expect "C  allowlist ABSENT (#926)         -> detected, fail-closed" 1 "do not commit credentials" "$t"

# D — an explicitly vetted shape. The bypass has to keep working or authors will delete the gate.
t="$(new_tree d)"
printf 'const key = "%s"; // pragma: allowlist secret\n' "$canary" > "$t/src/config.js"
printf '# a real exception\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
expect "D  pragma-tagged                   -> clean" 0 "secret-scan clean" "$t"

# The load-bearing one: the allowlist COVERS the canary's file, so a working gate reports clean —
# and any regression that resurrects the fail-open would report clean here too. It is only
# meaningful next to case A, which uses the same tree with a non-covering allowlist.
t="$(new_tree d2)"
printf '# covers the canary\nsrc/config.js\n' > "$t/.github/.secret-allowlist"
expect "D2 allowlist COVERS the finding    -> clean" 0 "secret-scan clean" "$t"

echo "== #932 — a malformed allowlist is a gate FAILURE, never a passing scan =="

# E — the original bug, verbatim. Before #928 this exact input printed "secret-scan clean".
t="$(new_tree e)"
printf '# exceptions\ndocs/EXAMPLE.md\n\ndocs/OTHER.md\n' > "$t/.github/.secret-allowlist"
expect "E  blank line                      -> rejected" 1 "blank or whitespace-only line" "$t"

# F — same defect wearing a disguise. `grep -F` reads a spaces-only line as the empty pattern too,
# and it is invisible in every diff and review UI.
t="$(new_tree f)"
printf '# exceptions\ndocs/EXAMPLE.md\n   \n' > "$t/.github/.secret-allowlist"
expect "F  whitespace-only line            -> rejected" 1 "blank or whitespace-only line" "$t"

# G — a trailing space makes the entry a fixed string that can never match: a DEAD exception the
# author believes is live. Opposite direction to E, same root: the file and grep have come apart.
t="$(new_tree g)"
printf '# exceptions\ndocs/EXAMPLE.md \n' > "$t/.github/.secret-allowlist"
expect "G  trailing whitespace             -> rejected" 1 "trailing whitespace or CR" "$t"

# H — a CRLF checkout does this to every line, silently, on a Windows clone.
t="$(new_tree h)"
printf '# exceptions\r\ndocs/EXAMPLE.md\r\n' > "$t/.github/.secret-allowlist"
expect "H  CRLF line endings               -> rejected" 1 "trailing whitespace or CR" "$t"

# I — the most likely author error: entries are FIXED strings, so `staging/*.md` matches the twelve
# literal characters `staging/*.md` and grants no exception whatsoever.
t="$(new_tree i)"
printf '# exceptions\nstaging/*.md\n' > "$t/.github/.secret-allowlist"
expect "I  glob metacharacter              -> rejected" 1 "glob metacharacter" "$t"

# J — a bare `.` is a substring of nearly every scanned line, so it allowlists the entire tree. The
# blank line's louder cousin: not "disables the scan", but "excuses everything".
t="$(new_tree j)"
printf '# exceptions\n.\n' > "$t/.github/.secret-allowlist"
expect "J  bare dot                        -> rejected" 1 "allowlists the entire tree" "$t"

# K — same hazard, quantified. `js` would silently excuse every JavaScript file in the repo.
t="$(new_tree k)"
printf '# exceptions\njs\n' > "$t/.github/.secret-allowlist"
expect "K  entry shorter than 3 chars      -> rejected" 1 "shorter than 3 characters" "$t"

# L — a file of nothing but comments. It fails CLOSED, so it is not dangerous; it is a lie about
# what the author has. They believe they hold exceptions and hold none.
t="$(new_tree l)"
printf '# exceptions\n# TODO: add them back\n' > "$t/.github/.secret-allowlist"
expect "L  sanitizes to ZERO patterns      -> rejected" 1 "ZERO patterns" "$t"

echo "== advisory — a stale entry must NOT fail an otherwise-clean build =="

# M — a stale exception is worth surfacing but grants an exception to nothing, so failing on it
# would punish a repo for a defect that cannot cause a miss. Note, don't block.
t="$(new_tree m)"; rm -f "$t/src/config.js"; printf 'hello\n' > "$t/src/config.js"
printf '# exceptions\ndocs/DELETED-LAST-YEAR.md\n' > "$t/.github/.secret-allowlist"
expect "M  stale path entry                -> clean, with a note" 0 "stale exception?" "$t"

echo "== the WORKFLOW copy — checks.yml's inline block must agree with the script =="

# checks.yml is a `workflow_call` reusable workflow consumed fleet-wide via @v1. Every checkout in
# it omits `repository:`, so the tree in scope is the CALLER's and this script does NOT exist there
# — the block has to stay inline. That makes it the one copy nothing was testing, and it carried
# #926's blank-line bypass long after the script was fixed: same allowlist, opposite verdicts.
#
# The block is EXTRACTED from the workflow at run time, never re-typed here. A re-typed copy is a
# third implementation that can agree with the test while disagreeing with what CI runs — the exact
# drift this whole issue is about.
WORKFLOW="$(cd "$HERE/../.." && pwd)/.github/workflows/checks.yml"
inline_block="$work/checks-inline.sh"
if [ ! -f "$WORKFLOW" ]; then
  fail "N  extract checks.yml inline block  -> workflow not found at $WORKFLOW"
elif ! python3 - "$WORKFLOW" "$inline_block" <<'PY'
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
steps = [s for j in yaml.safe_load(open(wf, encoding='utf-8'))['jobs'].values()
         for s in (j.get('steps') or []) if 'Secret scan' in str(s.get('name', ''))]
if len(steps) != 1:
    sys.exit(f"expected exactly 1 'Secret scan' step in checks.yml, found {len(steps)}")
open(out, 'w', encoding='utf-8').write(steps[0]['run'])
PY
then
  fail "N  extract checks.yml inline block  -> extraction failed"
else
  pass "N  extract checks.yml inline block"

  # expect_inline <case> <want_exit> <want_substring|-> <tree>
  #
  # `bash -e`, NOT plain `bash`. GitHub runs every `run:` block under `/usr/bin/bash -e {0}`, and
  # that single flag is the whole difference between the two copies: the canonical script sets
  # `-uo pipefail` and DELIBERATELY omits -e, so a `grep` that matches nothing (exit 1) is fine
  # there and ABORTS the workflow copy. Running the extracted block under plain `bash` measures a
  # shell that never executes it — this drill claimed to cover both copies and passed for weeks
  # while the workflow copy exited 1 on every clean tree, silently, which is the failure state a
  # gate can least afford.
  expect_inline() {
    local name="$1" want_exit="$2" want_text="$3" tree="$4" out rc
    out="$(cd "$tree" && bash -e "$inline_block" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want_exit" ]; then
      fail "$name — exit $rc, want $want_exit"
      printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
      return
    fi
    if [ "$want_text" != "-" ] && [[ "$out" != *"$want_text"* ]]; then
      fail "$name — exit $rc correct, but output never says '$want_text'"
      return
    fi
    pass "$name"
  }

  # O — the control. Both implementations must DETECT here, which is what makes P meaningful:
  # a drill where every case flips is usually measuring a broken harness, not the guard.
  t="$(new_tree wf_o)"
  printf '# a real exception\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
  expect_inline "O  workflow: non-covering allowlist -> detected" 1 "do not commit credentials" "$t"

  # P — THE REGRESSION THIS EXISTS FOR. One blank line made the workflow copy report clean against a
  # tree holding the canary, while the script correctly refused. Measured before the fix:
  #   inline=MISSED (scanner disabled)   canonical=REFUSED (malformed allowlist)
  t="$(new_tree wf_p)"
  printf '# exceptions\ndocs/EXAMPLE.md\n\ndocs/OTHER.md\n' > "$t/.github/.secret-allowlist"
  expect_inline "P  workflow: blank line (#926)      -> must NOT pass" 1 "-" "$t"

  # Q — allowlist ABSENT must stay fail-closed in the workflow copy too.
  t="$(new_tree wf_q)"
  expect_inline "Q  workflow: allowlist ABSENT       -> detected, fail-closed" 1 "do not commit credentials" "$t"

  # R — a file of only comments grants nothing; the workflow must say so rather than scan with an
  # empty exception set it silently treats as intentional.
  t="$(new_tree wf_r)"
  printf '# exceptions\n# TODO: add them back\n' > "$t/.github/.secret-allowlist"
  expect_inline "R  workflow: sanitizes to ZERO      -> rejected" 1 "ZERO patterns" "$t"

  # S — the allowlist genuinely covers the finding: clean. Without this, P/Q/R would all pass on a
  # workflow that simply fails every tree, which is not a working gate.
  t="$(new_tree wf_s)"
  printf '# covers the canary\nsrc/config.js\n' > "$t/.github/.secret-allowlist"
  expect_inline "S  workflow: allowlist COVERS it    -> clean" 0 "secret-scan clean" "$t"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "secret-scan self-test: all cases pass"
  exit 0
fi
echo "secret-scan self-test: $fails case(s) FAILED"
exit 1
