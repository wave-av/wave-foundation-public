#!/usr/bin/env bash
# test-human-review-gate.sh — self-test for the F4-#2 mandatory human-review gate on agent-authored
# WAS rule check_fns (WAS joint #3 Layer 3-5, scripts/check-agent-review-gate.sh).
#
# Proves, against an isolated fixture tree (no writes to the real repo):
#   (a) agent-authored rule, NO attestation                -> REFUSED
#   (b) agent-authored rule, valid matching attestation    -> PASSES
#   (c) agent-authored rule, stale (sha-mismatched) attest -> REFUSED
#   (d) human-authored rule, unaffected                    -> PASSES
# and then, against the REAL repo:
#   (e) frameworks/gates/test-workflow-policy.sh (the #873 brake) stays GREEN.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
GATE="$REPO_ROOT/scripts/check-agent-review-gate.sh"
BRAKE="$HERE/test-workflow-policy.sh"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

CHECKS_YML="$work/checks.yml"
LEDGER="$work/rule-authorship.jsonl"

cat > "$CHECKS_YML" <<'YML'
          # check_fn:ruleAgentNoReview begin
          if some_condition:
              w("ruleAgentNoReview", "no timeout")
          # check_fn:ruleAgentNoReview end
          # check_fn:ruleAgentValid begin
          if other_condition:
              w("ruleAgentValid", "no timeout")
          # check_fn:ruleAgentValid end
YML

# Compute the REAL current sha256 of ruleAgentValid's check_fn body the same way the gate does
# (delegate to check-fn-sha.sh so the test can't drift from the gate's own extraction logic).
VALID_SHA="$(bash "$REPO_ROOT/scripts/check-fn-sha.sh" ruleAgentValid --checks-yml "$CHECKS_YML" \
  | sed -n 's/^--- sha256:\(.*\) ---$/\1/p')"
[ -n "$VALID_SHA" ] || { echo "setup error: could not compute ruleAgentValid sha via check-fn-sha.sh" >&2; exit 1; }
STALE_SHA="0000000000000000000000000000000000000000000000000000000000000000"

cat > "$LEDGER" <<EOF
{"rule_id":"ruleAgentNoReview","record":"authorship","authorship":"agent","ts":"t0","by":"test-seed"}
{"rule_id":"ruleAgentValid","record":"authorship","authorship":"agent","ts":"t0","by":"test-seed"}
{"rule_id":"ruleAgentValid","record":"human_review","reviewer":"jake","ts":"t1","pr_or_commit":"PR#999","check_fn_sha":"$VALID_SHA","by":"test-seed"}
{"rule_id":"ruleAgentStale","record":"authorship","authorship":"agent","ts":"t0","by":"test-seed"}
{"rule_id":"ruleAgentStale","record":"human_review","reviewer":"jake","ts":"t1","pr_or_commit":"PR#999","check_fn_sha":"$STALE_SHA","by":"test-seed"}
{"rule_id":"ruleHuman","record":"authorship","authorship":"human","ts":"t0","by":"test-seed"}
EOF
# ruleAgentStale reuses ruleAgentValid's check_fn body (same text) but records a WRONG sha —
# proves mismatch detection independent of marker lookup.
cat >> "$CHECKS_YML" <<'YML'
          # check_fn:ruleAgentStale begin
          if other_condition:
              w("ruleAgentValid", "no timeout")
          # check_fn:ruleAgentStale end
YML

fail=0
check() {
  # expect: "pass" (rc must be 0) or "refuse" (rc must be nonzero)
  local desc="$1" rule="$2" expect="$3"
  set +e
  out="$(bash "$GATE" "$rule" --checks-yml "$CHECKS_YML" --authorship-ledger "$LEDGER" 2>&1)"
  rc=$?
  set -e
  local ok=0
  if [ "$expect" = "pass" ] && [ "$rc" -eq 0 ]; then ok=1; fi
  if [ "$expect" = "refuse" ] && [ "$rc" -ne 0 ]; then ok=1; fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS $desc (rc=$rc)"
  else
    echo "FAIL $desc: expected $expect, got rc=$rc"
    fail=1
  fi
  printf '%s\n' "$out" | sed 's/^/    /'
}

# (a) agent-authored, no attestation -> REFUSED
check "(a) agent-authored, NO attestation -> refused" ruleAgentNoReview refuse

# (b) agent-authored, valid matching attestation -> PASSES
check "(b) agent-authored, valid attestation -> passes" ruleAgentValid pass

# (c) agent-authored, stale (sha-mismatched) attestation -> REFUSED
check "(c) agent-authored, stale attestation -> refused" ruleAgentStale refuse

# (d) human-authored, unaffected -> PASSES
check "(d) human-authored, unaffected -> passes" ruleHuman pass

# (e) the real #873 brake stays green
echo "--- (e) real #873 brake (test-workflow-policy.sh) ---"
if bash "$BRAKE" > "$work/brake.out" 2>&1; then
  echo "PASS (e) brake GREEN"
else
  echo "FAIL (e) brake did not stay green:"
  sed 's/^/    /' "$work/brake.out"
  fail=1
fi

if [ "$fail" = 0 ]; then
  echo "✓ human-review gate self-test: all outcomes (a)-(e) as expected"
else
  echo "✗ human-review gate self-test FAILED" >&2
fi
exit "$fail"
