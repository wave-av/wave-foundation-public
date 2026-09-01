#!/usr/bin/env bash
# check-agent-review-gate.sh — the F4-#2 mandatory-human-review gate for agent-authored WAS rules
# (WAS joint #3 Layer 3-5). An agent-authored check_fn (written by the L3-1 authoring agent from
# untrusted proposal/incident text, NOT a human) must never reach `enforce` without an explicit,
# CURRENT human sign-off on the check_fn body itself — ordinary green CI is not sufficient, because
# an agent reading incident text / CI logs can be steered by adversarial content into a bad check.
#
# Read-only, non-destructive: consults the authorship ledger + checks.yml, exits 0 (clear) or
# non-zero (refuse) with an actionable message. Called by promote-rule.sh before it flips severity;
# also directly unit-testable in isolation (frameworks/gates/test-human-review-gate.sh).
#
# Cold-start / grandfather policy: a rule with NO authorship record at all is refused — authorship
# (human or agent) must be explicitly recorded (see rule-authorship.jsonl) before promotion. This
# never silently passes an unrecorded rule.
#
# Usage: check-agent-review-gate.sh <rule_id> --checks-yml <path> --authorship-ledger <path>
set -euo pipefail
die() { echo "check-agent-review-gate: $*" >&2; exit 1; }

RULE_ID="${1:-}"; shift || true
[ -n "$RULE_ID" ] || die "usage: check-agent-review-gate.sh <rule_id> --checks-yml <path> --authorship-ledger <path>"

CHECKS_YML=""
LEDGER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --checks-yml) CHECKS_YML="${2:-}"; shift 2 ;;
    --authorship-ledger) LEDGER="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$CHECKS_YML" ] && [ -f "$CHECKS_YML" ] || die "--checks-yml <path> required and must exist"
[ -n "$LEDGER" ] && [ -f "$LEDGER" ] || die "--authorship-ledger <path> required and must exist"

python3 - "$RULE_ID" "$CHECKS_YML" "$LEDGER" <<'PY'
import hashlib, json, sys

rule_id, checks_yml, ledger_path = sys.argv[1], sys.argv[2], sys.argv[3]

authorship_recs = []
review_recs = []
with open(ledger_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        if rec.get("rule_id") != rule_id:
            continue
        if rec.get("record") == "authorship":
            authorship_recs.append(rec)
        elif rec.get("record") == "human_review":
            review_recs.append(rec)

if not authorship_recs:
    sys.exit(f"REFUSED — no authorship record for '{rule_id}' in {ledger_path}. Cold-start policy: "
              f"authorship (human|agent) must be explicitly recorded before promotion; a rule of "
              f"unrecorded provenance never silently passes.")

authorship = authorship_recs[-1].get("authorship")  # append-only ledger: last record wins

if authorship == "human":
    print(f"PASS — '{rule_id}' is human-authored (ledger record: {authorship_recs[-1].get('by')}); "
          f"F4-#2 review gate does not apply.")
    sys.exit(0)

if authorship != "agent":
    sys.exit(f"REFUSED — '{rule_id}' has unrecognized authorship value {authorship!r} in {ledger_path} "
              f"(expected 'human' or 'agent'); refusing to promote a rule of ambiguous provenance.")

# authorship == "agent": require a CURRENT human_review attestation.
if not review_recs:
    sys.exit(f"REFUSED — '{rule_id}' is agent-authored and has NO human_review attestation. "
              f"Run: scripts/check-fn-sha.sh {rule_id}   (read the check_fn, get its sha256)\n"
              f"then: scripts/attest-rule-review.sh {rule_id} --reviewer <who> --check-fn-sha <sha> "
              f"--pr-or-commit <ref>")

review = review_recs[-1]  # latest attestation wins
attested_sha = review.get("check_fn_sha", "")

lines = open(checks_yml).read().splitlines()
begin_marker = f"# check_fn:{rule_id} begin"
end_marker = f"# check_fn:{rule_id} end"
start = end = None
for i, line in enumerate(lines):
    if start is None and line.strip() == begin_marker:
        start = i + 1
        continue
    if start is not None and line.strip() == end_marker:
        end = i
        break
if start is None or end is None:
    sys.exit(f"REFUSED — '{rule_id}' is agent-authored but its check_fn in {checks_yml} is not "
              f"delimited by '{begin_marker}' / '{end_marker}' markers; cannot bind the human_review "
              f"attestation to a specific check_fn body. Wrap the check_fn in the markers first.")

body = "\n".join(lines[start:end]) + "\n"
current_sha = hashlib.sha256(body.encode("utf-8")).hexdigest()

if attested_sha != current_sha:
    sys.exit(f"REFUSED — '{rule_id}' human_review attestation is STALE: attested check_fn_sha "
              f"({attested_sha[:12]}...) does not match the CURRENT check_fn body "
              f"({current_sha[:12]}...) in {checks_yml}. The check_fn was edited after review "
              f"(reviewer={review.get('reviewer')!r}, ts={review.get('ts')!r}). Get the current body "
              f"re-reviewed and re-attested via scripts/attest-rule-review.sh before promoting.")

print(f"PASS — '{rule_id}' is agent-authored with a CURRENT human_review attestation "
      f"(reviewer={review.get('reviewer')!r}, ts={review.get('ts')!r}, "
      f"pr_or_commit={review.get('pr_or_commit')!r}, sha={current_sha[:12]}...).")
PY
