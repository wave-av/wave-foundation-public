#!/usr/bin/env bash
# Fetch every wave-av repo's capabilities.json (from its default branch) into
# a single directory, ready for scripts/aggregate.ts.
#
# Output:
#   ${OUT_DIR}/<repo>.json   one per repo that has a capabilities.json
#
# Skips:
#   - private archived repos
#   - repos without a capabilities.json at the default branch (404 from gh api)
#
# Idempotent: re-run replaces existing files.
#
# Requires:
#   - gh CLI authenticated with `repo` scope
#   - GH_TOKEN env (when run from a workflow, the built-in GITHUB_TOKEN is enough)

set -euo pipefail

OUT_DIR="${OUT_DIR:-/tmp/caps}"
ORG="${ORG:-wave-av}"

mkdir -p "$OUT_DIR"
# Wipe stale files so the run is a clean snapshot, not an accumulation.
rm -f "$OUT_DIR"/*.json

# List every non-archived repo in the org. --jq strips fields we don't need;
# --paginate handles >100 repos transparently.
repos=$(gh repo list "$ORG" --no-archived --limit 200 --json name,defaultBranchRef --jq '.[] | "\(.name) \(.defaultBranchRef.name)"')

count=0
missing=0
while read -r name branch; do
  if [ -z "$name" ] || [ -z "$branch" ]; then continue; fi
  out="$OUT_DIR/$name.json"
  if gh api "/repos/$ORG/$name/contents/capabilities.json?ref=$branch" \
       -H "Accept: application/vnd.github.raw" > "$out" 2>/dev/null; then
    # gh api writes the raw bytes; verify it's JSON before counting.
    if jq empty < "$out" >/dev/null 2>&1; then
      count=$((count + 1))
    else
      rm -f "$out"
      missing=$((missing + 1))
    fi
  else
    rm -f "$out"
    missing=$((missing + 1))
  fi
done <<< "$repos"

echo "fetched $count, missing $missing"
