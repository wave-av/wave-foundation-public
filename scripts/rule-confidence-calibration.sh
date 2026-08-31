#!/usr/bin/env bash
# rule-confidence-calibration.sh — the F4-#3 empirical-confidence-calibration consult for
# agent-authored WAS rules (WAS joint #3 Layer 3-4, confidence-gated-autonomy).
#
# scripts/author-rule.mjs emits a PREDICTED calibrated confidence score per agent-authored rule at
# authoring time (frameworks/gates/rule-authoring-confidence.jsonl, record:"predicted"). As reality
# lands, an outcome record is appended (record:"outcome": "shadow-clean" | "promotion-stuck" |
# "reverted-by-tripwire"). This script answers ONE question for a candidate rule about to be
# auto-promoted: "at this rule's predicted-confidence CLASS, what fraction of past agent-authored
# rules with a recorded outcome came out clean?" — the empirical calibration.
#
# Auto-promote is permitted ONLY when:
#   - the rule is human-authored (calibration does not apply — same scope as the L3-5 review gate), OR
#   - the rule is agent-authored AND the empirical calibration at its confidence class has
#     >= --min-samples real outcome records AND >= --threshold percent of them are clean.
#
# Cold-start (fewer than --min-samples outcome records at that confidence class) NEVER silently
# passes: it refuses with "insufficient-calibration -> human-required". Below-threshold refuses too.
# Both failure modes route to the SAME place: a human makes the promote/no-promote call by hand
# (the F4-#2 attestation path is unaffected either way).
#
# Usage:
#   rule-confidence-calibration.sh <rule_id> --confidence-ledger <path> --authorship-ledger <path>
#                                   [--min-samples N] [--threshold PCT]
set -euo pipefail
die() { echo "rule-confidence-calibration: $*" >&2; exit 1; }

RULE_ID="${1:-}"; shift || true
[ -n "$RULE_ID" ] || die "usage: rule-confidence-calibration.sh <rule_id> --confidence-ledger <path> --authorship-ledger <path> [--min-samples N] [--threshold PCT]"

CONFIDENCE_LEDGER=""
AUTHORSHIP_LEDGER=""
MIN_SAMPLES=5
THRESHOLD=95
while [ $# -gt 0 ]; do
  case "$1" in
    --confidence-ledger) CONFIDENCE_LEDGER="${2:-}"; shift 2 ;;
    --authorship-ledger) AUTHORSHIP_LEDGER="${2:-}"; shift 2 ;;
    --min-samples) MIN_SAMPLES="${2:-}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$CONFIDENCE_LEDGER" ] && [ -f "$CONFIDENCE_LEDGER" ] || die "--confidence-ledger <path> required and must exist"
[ -n "$AUTHORSHIP_LEDGER" ] && [ -f "$AUTHORSHIP_LEDGER" ] || die "--authorship-ledger <path> required and must exist"

python3 - "$RULE_ID" "$CONFIDENCE_LEDGER" "$AUTHORSHIP_LEDGER" "$MIN_SAMPLES" "$THRESHOLD" <<'PY'
import json, sys

rule_id, conf_path, auth_path, min_samples, threshold = (
    sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), float(sys.argv[5]))

CLEAN = {"shadow-clean"}
BAD = {"promotion-stuck", "reverted-by-tripwire"}

def read_jsonl(path):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                yield json.loads(line)

# --- authorship: calibration does not apply to human-authored rules (same scope as L3-5) ---
authorship = None
for rec in read_jsonl(auth_path):
    if rec.get("rule_id") == rule_id and rec.get("record") == "authorship":
        authorship = rec.get("authorship")  # append-only: last wins
if authorship is None:
    sys.exit(f"REFUSED — no authorship record for '{rule_id}' in {auth_path}; cannot determine "
              f"whether the confidence-calibration consult applies.")
if authorship == "human":
    print(f"PASS — '{rule_id}' is human-authored; confidence-calibration consult does not apply.")
    sys.exit(0)
if authorship != "agent":
    sys.exit(f"REFUSED — '{rule_id}' has unrecognized authorship value {authorship!r}.")

# --- predicted confidence for this rule, and its bucketed class (nearest 10) ---
predicted = None
for rec in read_jsonl(conf_path):
    if rec.get("rule_id") == rule_id and rec.get("record") == "predicted":
        predicted = rec.get("predicted_confidence")  # append-only: last wins
if predicted is None:
    sys.exit(f"REFUSED — no predicted_confidence record for '{rule_id}' in {conf_path}; "
              f"scripts/author-rule.mjs must emit one at authoring time. Refusing to calibrate blind.")
predicted = float(predicted)
klass = int(predicted // 10) * 10

# --- gather real history: latest outcome per rule_id, restricted to the same confidence class ---
predicted_by_rule = {}
outcome_by_rule = {}
for rec in read_jsonl(conf_path):
    rid = rec.get("rule_id")
    if rec.get("record") == "predicted":
        predicted_by_rule[rid] = float(rec.get("predicted_confidence"))
    elif rec.get("record") == "outcome":
        outcome_by_rule[rid] = rec.get("outcome")

samples = []
for rid, pred in predicted_by_rule.items():
    if int(pred // 10) * 10 != klass:
        continue
    outcome = outcome_by_rule.get(rid)
    if outcome is None:
        continue  # no outcome landed yet — not usable history
    if outcome not in CLEAN and outcome not in BAD:
        sys.exit(f"REFUSED — rule '{rid}' has unrecognized outcome value {outcome!r} in {conf_path}; "
                  f"refusing to compute calibration over an unverifiable history.")
    samples.append((rid, outcome))

n = len(samples)
if n < min_samples:
    sys.exit(f"REFUSED — insufficient-calibration -> human-required. Confidence class [{klass},{klass+10}) "
              f"has only {n} real outcome sample(s) (need >= {min_samples}) in {conf_path}. "
              f"Cold-start: a human must make the promote/no-promote call for '{rule_id}' by hand.")

clean_n = sum(1 for _, o in samples if o in CLEAN)
calibration_pct = 100.0 * clean_n / n
if calibration_pct < threshold:
    sys.exit(f"REFUSED — empirical calibration {calibration_pct:.1f}% < required {threshold:.1f}% for "
              f"confidence class [{klass},{klass+10}) (n={n}, clean={clean_n}) in {conf_path}. "
              f"Below-threshold: a human must make the promote/no-promote call for '{rule_id}' by hand.")

print(f"PASS — '{rule_id}' confidence class [{klass},{klass+10}) empirically calibrated at "
      f"{calibration_pct:.1f}% clean (n={n}, clean={clean_n}) >= {threshold:.1f}% threshold "
      f"(min_samples={min_samples}).")
PY
