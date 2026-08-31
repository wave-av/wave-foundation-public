#!/usr/bin/env bash
# test-ci-efficiency.sh: self-test for the CI-efficiency static gate (#3932,
# gha-billing-efficiency P3).
#
# The gate has two halves that must never drift:
#   1. frameworks/gates/scripts/ci-efficiency-check.py: the canonical checker (local
#      runs, the scheduled census pass, and this suite).
#   2. The VERBATIM inline twin inside .github/workflows/checks.yml (job ci-efficiency):
#      checks.yml is a reusable workflow that runs on the CALLER's checkout, and consumer
#      repos carry no foundation scripts, so the live gate inlines the python the same way
#      the secret-scan step does.
#
# The sync check byte-compares the twin against the canonical file (identical bytes cannot
# disagree; stronger than drilling both behaviorally). The fixture drills then pin each
# rule's behavior: one workflow file per violation class plus clean ones, the advisory
# contract (findings warn, the exit stays 0), the strict contract (the future blocking
# mode exits 1 and prints ::error::), and the no-args discovery pass.
#
# Usage:  bash frameworks/gates/test-ci-efficiency.sh
# Exit:   0 = every case behaved as specified; 1 = at least one case regressed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANONICAL="$HERE/scripts/ci-efficiency-check.py"
CHECKS_YML="$HERE/../../.github/workflows/checks.yml"
FIXTURES="$HERE/fixtures/ci-efficiency"
JOB_ID="ci-efficiency"
STEP_NAME="CI-efficiency static check (advisory)"

[ -f "$CANONICAL" ] || { echo "error: $CANONICAL not found" >&2; exit 1; }
[ -f "$CHECKS_YML" ] || { echo "error: $CHECKS_YML not found" >&2; exit 1; }
[ -d "$FIXTURES" ] || { echo "error: $FIXTURES not found" >&2; exit 1; }

python3 -c "import yaml" 2>/dev/null || pip install --quiet --disable-pip-version-check pyyaml

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# --- sync: the inline twin in checks.yml must be byte-identical to the canonical script ---
twin_py="$work/ci-efficiency-twin.py"
extract_rc=0
python3 - "$CHECKS_YML" "$JOB_ID" "$STEP_NAME" "$twin_py" <<'EXTRACT' || extract_rc=$?
import sys, yaml

checks_yml, job_id, step_name, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
doc = yaml.safe_load(open(checks_yml))
job = (doc.get("jobs") or {}).get(job_id)
if not isinstance(job, dict):
    sys.exit(f"error: job '{job_id}' not found in {checks_yml}")
run_src = None
for step in job.get("steps") or []:
    if isinstance(step, dict) and step.get("name") == step_name:
        run_src = step.get("run")
        break
if run_src is None:
    sys.exit(f"error: step '{step_name}' not found in job '{job_id}'")

# The step's run: block ends with a python3 heredoc; YAML block-scalar parsing already
# dedented it, so slice the body between the opening marker and the closing bare PY line
# (same extraction the workflow-policy harness uses).
lines = run_src.splitlines()
start = end = None
for i, line in enumerate(lines):
    if start is None and "<<'PY'" in line:
        start = i + 1
        continue
    if start is not None and line.strip() == "PY":
        end = i
        break
if start is None or end is None:
    sys.exit("error: could not locate the python heredoc in the step's run: block")

open(out_path, "w").write("\n".join(lines[start:end]) + "\n")
EXTRACT

if [ "$extract_rc" -ne 0 ]; then
  fail "sync: could not extract the inline twin from checks.yml (job '$JOB_ID', step '$STEP_NAME')"
elif cmp -s "$twin_py" "$CANONICAL"; then
  pass "sync: the checks.yml inline twin is byte-identical to the canonical script"
else
  fail "sync: the checks.yml inline twin drifted from frameworks/gates/scripts/ci-efficiency-check.py. Re-copy the canonical file into the job's heredoc verbatim (same indentation pattern)."
  diff "$CANONICAL" "$twin_py" | head -10 | sed 's/^/       /'
fi

# --- expect: advisory contract against one fixture ---
# expect <case> <fixture> <want_findings> <want_rules...>
#   Exit must be 0 (advisory never blocks), the finding count must match, and every named
#   rule must appear as a bracketed ci-efficiency[RULE] tag. Markers match on the closed
#   bracket so FAST-CRON never satisfies a FAST-CRON-ON-EXPENSIVE assertion.
expect() {
  local case="$1" fixture="$2" want="$3"
  shift 3
  local out rc n m ok
  out="$(python3 "$CANONICAL" "$fixture" 2>&1)"; rc=$?
  ok=1
  if [ "$rc" -ne 0 ]; then
    fail "$case: exit $rc, want 0 (the advisory contract never blocks)"
    printf '%s\n' "$out" | sed 's/^/       /' | head -5
    ok=0
  fi
  n="$(printf '%s\n' "$out" | grep -c '^::warning::ci-efficiency\[' || true)"
  if [ "$ok" -eq 1 ] && [ "$n" -ne "$want" ]; then
    fail "$case: $n warning(s), want $want"
    printf '%s\n' "$out" | sed 's/^/       /' | head -5
    ok=0
  fi
  for m in "$@"; do
    if [ "$ok" -eq 1 ] && ! [[ "$out" == *"ci-efficiency[$m]"* ]]; then
      fail "$case: no finding tagged ci-efficiency[$m]"
      ok=0
    fi
  done
  [ "$ok" -eq 1 ] && pass "$case: exit 0, $want finding(s) ($*)"
  return 0
}

# Clean fixtures: zero findings, and the advisory contract holds.
for good in "$FIXTURES"/good-*.yml; do
  expect "clean $(basename "$good")" "$good" 0
done

# Violation fixtures: one file per class (bad-d carries two findings by design: the cron
# itself plus the paid runner under it).
expect "DOUBLE-FIRE (schedule+push+pr)" "$FIXTURES/bad-a-double-fire.yml" 1 DOUBLE-FIRE
expect "DOUBLE-FIRE (schedule+pr)" "$FIXTURES/bad-a2-schedule-pr.yml" 1 DOUBLE-FIRE
expect "COMMENT-FANOUT (unguarded)" "$FIXTURES/bad-b-comment-fanout.yml" 1 COMMENT-FANOUT
expect "FAST-CRON (*/30)" "$FIXTURES/bad-c-fast-cron.yml" 1 FAST-CRON
expect "FAST-CRON (* minutes)" "$FIXTURES/bad-c2-cron-every-minute.yml" 1 FAST-CRON
expect "FAST-CRON + ON-EXPENSIVE" "$FIXTURES/bad-d-fast-cron-expensive.yml" 2 FAST-CRON FAST-CRON-ON-EXPENSIVE

# --- strict: the future blocking mode (the #3932 flip is --strict + dropping the
# job-level continue-on-error; nothing else changes) ---
strict_out="$(python3 "$CANONICAL" --strict "$FIXTURES/bad-d-fast-cron-expensive.yml" 2>&1)"; strict_rc=$?
if [ "$strict_rc" -eq 1 ] && [[ "$strict_out" == *"::error::ci-efficiency[FAST-CRON]"* ]] && [[ "$strict_out" == *"::error::ci-efficiency[FAST-CRON-ON-EXPENSIVE]"* ]]; then
  pass "strict: findings exit 1 and print ::error:: (the blocking flip works)"
else
  fail "strict: bad-d --strict gave exit $strict_rc; want exit 1 with two ::error:: findings"
  printf '%s\n' "$strict_out" | sed 's/^/       /' | head -5
fi
clean_strict_rc=0
python3 "$CANONICAL" --strict "$FIXTURES/good-clean.yml" >/dev/null 2>&1 || clean_strict_rc=$?
if [ "$clean_strict_rc" -eq 0 ]; then
  pass "strict: a clean file stays exit 0 under --strict"
else
  fail "strict: good-clean --strict gave exit $clean_strict_rc; want 0"
fi

# --- discovery: no args means every .github/workflows/*.{yml,yaml} under cwd ---
disc_dir="$work/discovery"
mkdir -p "$disc_dir/.github/workflows"
cp "$FIXTURES/good-clean.yml" "$disc_dir/.github/workflows/"
cp "$FIXTURES/bad-c-fast-cron.yml" "$disc_dir/.github/workflows/"
cp "$FIXTURES/good-cron-hourly.yml" "$disc_dir/.github/workflows/bonus.yaml"
disc_out="$(cd "$disc_dir" && python3 "$CANONICAL" 2>&1)"; disc_rc=$?
disc_n="$(printf '%s\n' "$disc_out" | grep -c '^::warning::ci-efficiency\[' || true)"
if [ "$disc_rc" -eq 0 ] && [ "$disc_n" -eq 1 ] && [[ "$disc_out" == *"scanned 3 workflow file(s)"* ]]; then
  pass "discovery: no args scans every workflow file, including .yaml (3 scanned, 1 finding)"
else
  fail "discovery: exit $disc_rc, $disc_n finding(s); want exit 0, 1 finding over 3 files"
  printf '%s\n' "$disc_out" | sed 's/^/       /' | head -5
fi

# --- twin drill: the extracted inline copy must behave like the canonical script ---
if [ "$extract_rc" -eq 0 ]; then
  twin_out="$(python3 "$twin_py" "$FIXTURES/bad-d-fast-cron-expensive.yml" 2>&1)"; twin_rc=$?
  canon_out="$(python3 "$CANONICAL" "$FIXTURES/bad-d-fast-cron-expensive.yml" 2>&1)"; canon_rc=$?
  if [ "$twin_rc" -eq "$canon_rc" ] && [ "$twin_out" = "$canon_out" ]; then
    pass "twin: the extracted checks.yml copy behaves identically to the canonical script"
  else
    fail "twin: the extracted copy's output diverged from the canonical script"
    diff <(printf '%s\n' "$canon_out") <(printf '%s\n' "$twin_out") | head -10 | sed 's/^/       /'
  fi
fi

if [ "$fails" -eq 0 ]; then
  echo "ci-efficiency self-test: sync + all fixture, strict, discovery and twin cases behave as specified"
else
  echo "ci-efficiency self-test FAILED ($fails case(s))" >&2
fi
exit $((fails > 0 ? 1 : 0))
