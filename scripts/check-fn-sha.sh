#!/usr/bin/env bash
# check-fn-sha.sh — print the exact check_fn body (and its sha256) for a WAS rule, so a human
# reviewer can read the real code and hand the resulting hash to attest-rule-review.sh. This is
# the binding mechanism for the F4-#2 human-review gate (L3-5): the sha binds a sign-off to the
# EXACT reviewed check_fn text, so a post-review edit invalidates the attestation.
#
# Convention: an agent-authored rule's check_fn in checks.yml MUST be delimited by:
#   # check_fn:<rule_id> begin
#   ... check body ...
#   # check_fn:<rule_id> end
#
# Usage: check-fn-sha.sh <rule_id> [--checks-yml <path>]
set -euo pipefail
die() { echo "check-fn-sha: $*" >&2; exit 1; }

RULE_ID="${1:-}"; shift || true
[ -n "$RULE_ID" ] || die "usage: check-fn-sha.sh <rule_id> [--checks-yml <path>]"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
CHECKS_YML="$REPO_ROOT/.github/workflows/checks.yml"
while [ $# -gt 0 ]; do
  case "$1" in
    --checks-yml) CHECKS_YML="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -f "$CHECKS_YML" ] || die "$CHECKS_YML not found"

python3 - "$CHECKS_YML" "$RULE_ID" <<'PY'
import hashlib, sys
checks_yml, rule_id = sys.argv[1], sys.argv[2]
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
    sys.exit(f"check-fn-sha: markers '{begin_marker}' / '{end_marker}' not found in {checks_yml} — "
              f"an agent-authored rule's check_fn must be wrapped in these markers before it can be reviewed")
body = "\n".join(lines[start:end]) + "\n"
digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
print(f"--- check_fn:{rule_id} ({end - start} lines) ---")
print(body)
print(f"--- sha256:{digest} ---")
PY
