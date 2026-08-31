#!/usr/bin/env bash
# test-node-suite-discovery.sh — self-test for the `node-suites` step in .github/workflows/self-check.yml.
#
# WHAT IT PINS (#964). The step already refuses to report green on ZERO DISCOVERED suites. It could
# not see the next zero: a suite that IS discovered and registers NO tests. `node --test` collects
# nothing from it, every other suite passes, and the job goes green — so the file reads on the repo
# as coverage while providing none. "This suite asserts nothing" and "this suite passed" produced
# identical output, which is the same two-zeros shape as #944 one layer up.
#
# HOW. The step body is EXTRACTED from the workflow with PyYAML at run time, never re-typed here.
# A re-typed copy is a second implementation that can agree with this test while disagreeing with
# what CI actually runs — the drift these gates exist to prevent.
#
# Each case builds a throwaway git repo under mktemp with its own tracked *.test.mjs files and runs
# the real step body inside it. Nothing is written into this repo.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORKFLOW="${WAVE_SELF_CHECK_WORKFLOW:-$ROOT/.github/workflows/self-check.yml}"
[ -f "$WORKFLOW" ] || { echo "error: workflow not found at $WORKFLOW" >&2; exit 2; }

command -v node >/dev/null 2>&1 || { echo "error: node not on PATH" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# --- extract the step body -----------------------------------------------------------------------
STEP="$work/node-suites-step.sh"
if ! python3 - "$WORKFLOW" "$STEP" <<'PY'
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
steps = [s for j in yaml.safe_load(open(wf, encoding='utf-8'))['jobs'].values()
         for s in (j.get('steps') or [])
         if 'tracked *.test.mjs' in str(s.get('name', ''))]
if len(steps) != 1:
    sys.exit(f"expected exactly 1 node-suites step, found {len(steps)}")
open(out, 'w', encoding='utf-8').write(steps[0]['run'])
PY
then
  echo "  FAIL could not extract the node-suites step from $WORKFLOW"
  exit 1
fi
pass "extracted the node-suites step from self-check.yml"

# --- fixtures ------------------------------------------------------------------------------------
# A suite with real assertions.
good_suite() {
  printf 'import { test } from "node:test";\nimport assert from "node:assert";\ntest("real", () => { assert.equal(1, 1); });\n'
}
# Imports cleanly, registers NOTHING. The defect under test: an early return leaves the file valid
# and empty, which is indistinguishable from "passed" to an aggregate runner.
empty_suite() {
  printf 'import { test } from "node:test";\nconst ENABLED = false;\nif (!ENABLED) { /* early-out: registers no tests */ } else {\n  test("never registered", () => {});\n}\n'
}
# A genuinely failing suite — must be reported as FAILED, never bucketed as "empty".
failing_suite() {
  printf 'import { test } from "node:test";\nimport assert from "node:assert";\ntest("broken", () => { assert.equal(1, 2); });\n'
}
# Registers no tests and asserts by EXIT CODE, declaring itself with the marker. Real coverage.
harness_suite() {
  printf '// node-suites: exit-code-harness\nif (1 !== 1) { process.exit(1); }\nconsole.log("harness ok");\n'
}
# The same declared harness, but genuinely failing. The marker must not mute a red suite.
harness_failing_suite() {
  printf '// node-suites: exit-code-harness\nconsole.error("harness assertion failed");\nprocess.exit(1);\n'
}

# make_repo <name> <spec>... where spec is name:kind (kind = good|empty|failing)
make_repo() {
  local d="$work/$1"; shift
  mkdir -p "$d"
  git init -q -b main "$d"
  git -C "$d" config user.email drill@wave.online
  git -C "$d" config user.name drill
  # The step shells out to scripts/tap-count-real-tests.mjs (#1047) relative to cwd, which in the
  # real job is the checkout. These fixture repos are throwaway trees under mktemp, so the helper
  # has to be staged into each one — copied from THIS repo, never re-typed, so the drill always
  # exercises the helper that actually ships. Case I deletes it again to prove the step fails loudly
  # when it is absent rather than scoring every suite as hollow.
  mkdir -p "$d/scripts"
  cp "$ROOT/scripts/tap-count-real-tests.mjs" "$d/scripts/tap-count-real-tests.mjs"
  local spec name kind
  for spec in "$@"; do
    name="${spec%%:*}"; kind="${spec##*:}"
    mkdir -p "$(dirname "$d/$name")"
    case "$kind" in
      good)            good_suite            > "$d/$name" ;;
      empty)           empty_suite           > "$d/$name" ;;
      failing)         failing_suite         > "$d/$name" ;;
      harness)         harness_suite         > "$d/$name" ;;
      harness_failing) harness_failing_suite > "$d/$name" ;;
    esac
  done
  git -C "$d" add -A
  # --allow-empty so the no-suites case (F) still produces a commit, and BOTH streams silenced:
  # this function returns its path on stdout, so any stray git chatter becomes part of the path the
  # caller cds into. git reports "nothing to commit" on STDOUT, which `2>/dev/null` alone misses.
  git -C "$d" commit -q --allow-empty -m 'test fixtures' >/dev/null 2>&1
  printf '%s' "$d"
}

# expect <case> <want_exit> <want_substring|-> <repo>
expect() {
  local name="$1" want_exit="$2" want_text="$3" repo="$4" out rc
  out="$(cd "$repo" && bash "$STEP" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want_exit" ]; then
    fail "$name — exit $rc, want $want_exit"
    printf '%s\n' "$out" | tail -6 | sed 's/^/       | /'
    return
  fi
  if [ "$want_text" != "-" ] && ! printf '%s' "$out" | grep -qF "$want_text"; then
    fail "$name — exit $rc correct, but output never says '$want_text'"
    printf '%s\n' "$out" | tail -6 | sed 's/^/       | /'
    return
  fi
  pass "$name"
}

echo "== node-suites: a discovered suite must actually assert something =="

# A — THE CONTROL. Every suite real: green. This passes against the unfixed step too, and must —
# it is what proves the other cases measure the guard rather than a broken harness.
expect "A  all suites register tests        -> green" 0 "-" \
  "$(make_repo a a.test.mjs:good b.test.mjs:good)"

# B — THE REGRESSION THIS EXISTS FOR. One empty suite among healthy ones. Pre-fix: green.
expect "B  one suite registers ZERO tests   -> REFUSED" 1 "registered ZERO tests" \
  "$(make_repo b a.test.mjs:good hollow.test.mjs:empty)"

# C — the empty suite is named, so the failure is actionable rather than a bare count.
expect "C  refusal names the hollow suite   -> names it" 1 "hollow.test.mjs" \
  "$(make_repo c a.test.mjs:good hollow.test.mjs:empty)"

# D — every suite empty. The most dangerous shape: a repo with "full coverage" asserting nothing.
expect "D  ALL suites empty                 -> REFUSED" 1 "registered ZERO tests" \
  "$(make_repo d x.test.mjs:empty y.test.mjs:empty)"

# E — a real failure must be reported AS a failure, not swallowed into the zero-tests bucket.
# Without this, a fix that simply failed on everything would pass B/C/D.
expect "E  a genuinely failing suite        -> reported as FAILED" 1 "suite(s) FAILED" \
  "$(make_repo e a.test.mjs:good bad.test.mjs:failing)"

# F — zero discovered suites stays a hard failure (the behaviour #963 added; must not regress).
expect "F  no suites at all                 -> REFUSED" 1 "Refusing to report green on zero tests" \
  "$(make_repo f)"

# G — the declared exception. A self-contained harness asserting by EXIT CODE registers no tests but
# is real coverage (scripts/gate-scope-conformance.test.mjs is one). It must pass — and only because
# the marker is present, which is what keeps silence from being the default.
expect "G  exit-code harness, DECLARED      -> green" 0 "exit-code harness (declared)" \
  "$(make_repo g a.test.mjs:good harness.test.mjs:harness)"

# H — the marker must not become a blanket mute. A DECLARED harness that actually FAILS has to be
# reported as a failure; otherwise the opt-out would be a way to silence a red suite.
expect "H  declared harness that FAILS      -> reported as FAILED" 1 "suite(s) FAILED" \
  "$(make_repo h a.test.mjs:good broken.test.mjs:harness_failing)"

# I — a suite in a SUBDIRECTORY. Every case above lives at the repo root, where node's relative
# spelling of the file-level subtest is indistinguishable from a bare basename. With a directory
# component the two come apart (node 22/24 print `sub/deep.test.mjs`), so this is what proves the
# discriminator handles the shape every REAL suite in this repo has — they all live under scripts/.
expect "I  hollow suite in a SUBDIRECTORY   -> REFUSED" 1 "registered ZERO tests" \
  "$(make_repo i a.test.mjs:good sub/deep.test.mjs:empty)"

# J — the step now depends on scripts/tap-count-real-tests.mjs (#1047), so the disappearance of that
# helper has to be a LOUD failure. Both silent directions are fail-open in opposite ways: an empty
# `real` read as 0 marks every suite hollow, and a `|| true` marks every suite fine. Delete the
# helper from a repo whose suites are otherwise healthy — a green here would mean the step stopped
# measuring anything.
repo_j="$(make_repo j a.test.mjs:good)"
rm -f "$repo_j/scripts/tap-count-real-tests.mjs"
expect "J  helper MISSING                   -> hard FAIL, never silently 0" 1 "tap-count-real-tests.mjs failed" \
  "$repo_j"

echo
if [ "$fails" -eq 0 ]; then
  echo "node-suite-discovery self-test: all cases pass"
  exit 0
fi
echo "node-suite-discovery self-test: $fails case(s) FAILED"
exit 1
