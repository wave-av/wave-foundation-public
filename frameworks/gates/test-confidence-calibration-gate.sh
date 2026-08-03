#!/usr/bin/env bash
# test-confidence-calibration-gate.sh — self-test for the F4-#3 empirical-confidence-calibration
# consult (WAS joint #3 Layer 3-4, scripts/rule-confidence-calibration.sh).
#
# Proves, against an isolated fixture tree (no writes to the real repo/ledgers):
#   (a) agent-authored rule, calibrated history >= threshold + valid L3-5 attestation -> PASSES
#   (b) same rule, but thin history (cold-start, < min-samples)                       -> REFUSED
#   (c) history at the class, but below the calibration threshold                     -> REFUSED
#   (d) human-authored rule, unaffected (calibration does not apply)                  -> PASSES
# and then, against the REAL repo:
#   (e) frameworks/gates/test-workflow-policy.sh (the #873 brake) stays GREEN.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
GATE="$REPO_ROOT/scripts/rule-confidence-calibration.sh"
BRAKE="$HERE/test-workflow-policy.sh"
L35_TEST="$HERE/test-human-review-gate.sh"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

AUTH_LEDGER="$work/rule-authorship.jsonl"
cat > "$AUTH_LEDGER" <<'EOF'
{"rule_id":"ruleCalibratedOK","record":"authorship","authorship":"agent","ts":"t0","by":"test-seed"}
{"rule_id":"ruleColdStart","record":"authorship","authorship":"agent","ts":"t0","by":"test-seed"}
{"rule_id":"ruleBelowThreshold","record":"authorship","authorship":"agent","ts":"t0","by":"test-seed"}
{"rule_id":"ruleHuman","record":"authorship","authorship":"human","ts":"t0","by":"test-seed"}
EOF

# --- (a) calibrated history: 6 past rules in the [90,100) class, 6 clean -> 100% >= 95% threshold ---
CONF_A="$work/confidence-calibrated.jsonl"
{
  for i in 1 2 3 4 5 6; do
    echo "{\"rule_id\":\"hist${i}a\",\"record\":\"predicted\",\"predicted_confidence\":92,\"ts\":\"t0\"}"
    echo "{\"rule_id\":\"hist${i}a\",\"record\":\"outcome\",\"outcome\":\"shadow-clean\",\"ts\":\"t1\"}"
  done
  echo '{"rule_id":"ruleCalibratedOK","record":"predicted","predicted_confidence":93,"ts":"t0"}'
} > "$CONF_A"

# --- (b) cold-start: same rule_id, but only 2 outcome samples exist at its class (< 5 min-samples) ---
CONF_B="$work/confidence-coldstart.jsonl"
{
  for i in 1 2; do
    echo "{\"rule_id\":\"hist${i}b\",\"record\":\"predicted\",\"predicted_confidence\":92,\"ts\":\"t0\"}"
    echo "{\"rule_id\":\"hist${i}b\",\"record\":\"outcome\",\"outcome\":\"shadow-clean\",\"ts\":\"t1\"}"
  done
  echo '{"rule_id":"ruleColdStart","record":"predicted","predicted_confidence":93,"ts":"t0"}'
} > "$CONF_B"

# --- (c) below-threshold: 6 samples at the class, only 3 clean (50% < 95%) ---
CONF_C="$work/confidence-below.jsonl"
{
  for i in 1 2 3; do
    echo "{\"rule_id\":\"hist${i}c\",\"record\":\"predicted\",\"predicted_confidence\":92,\"ts\":\"t0\"}"
    echo "{\"rule_id\":\"hist${i}c\",\"record\":\"outcome\",\"outcome\":\"shadow-clean\",\"ts\":\"t1\"}"
  done
  for i in 4 5 6; do
    echo "{\"rule_id\":\"hist${i}c\",\"record\":\"predicted\",\"predicted_confidence\":92,\"ts\":\"t0\"}"
    echo "{\"rule_id\":\"hist${i}c\",\"record\":\"outcome\",\"outcome\":\"reverted-by-tripwire\",\"ts\":\"t1\"}"
  done
  echo '{"rule_id":"ruleBelowThreshold","record":"predicted","predicted_confidence":93,"ts":"t0"}'
} > "$CONF_C"

fail=0
check() {
  local desc="$1" rule="$2" conf_ledger="$3" expect="$4"
  set +e
  out="$(bash "$GATE" "$rule" --confidence-ledger "$conf_ledger" --authorship-ledger "$AUTH_LEDGER" 2>&1)"
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

# (a) calibrated history >= threshold, PLUS a valid L3-5 attestation is required for promote-rule.sh's
#     autonomous path — proven directly by test-human-review-gate.sh case (b) below (same gate, unchanged).
#     Here we prove the calibration half of the AND: calibrated history >= threshold -> PASSES.
check "(a) calibrated history >= threshold -> passes" ruleCalibratedOK "$CONF_A" pass

# (b) cold-start (thin history) -> REFUSED insufficient-calibration
check "(b) cold-start (n<min-samples) -> refused" ruleColdStart "$CONF_B" refuse

# (c) history below threshold -> REFUSED
check "(c) history below threshold -> refused" ruleBelowThreshold "$CONF_C" refuse

# (d) human-authored, unaffected -> PASSES (any ledger; authorship short-circuits before it's read)
check "(d) human-authored, unaffected -> passes" ruleHuman "$CONF_A" pass

# (e) both underlying promote-rule.sh gates stay green/enforced: the #873 brake, AND the L3-5
#     human-review gate (unmodified by this change — proves the calibration consult is ADDITIVE,
#     not a regression of the mandatory human-review requirement).
echo "--- (e1) real #873 brake (test-workflow-policy.sh) ---"
if bash "$BRAKE" > "$work/brake.out" 2>&1; then
  echo "PASS (e1) brake GREEN"
else
  echo "FAIL (e1) brake did not stay green:"
  sed 's/^/    /' "$work/brake.out"
  fail=1
fi

echo "--- (e2) L3-5 human-review gate self-test (test-human-review-gate.sh) still enforced ---"
if bash "$L35_TEST" > "$work/l35.out" 2>&1; then
  echo "PASS (e2) L3-5 human-review gate self-test still passes (not regressed)"
else
  echo "FAIL (e2) L3-5 human-review gate self-test regressed:"
  sed 's/^/    /' "$work/l35.out"
  fail=1
fi

if [ "$fail" = 0 ]; then
  echo "✓ confidence-calibration gate self-test: all outcomes (a)-(e) as expected"
else
  echo "✗ confidence-calibration gate self-test FAILED" >&2
fi
exit "$fail"
