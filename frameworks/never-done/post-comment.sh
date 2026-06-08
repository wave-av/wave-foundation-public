#!/usr/bin/env bash
# post-comment.sh
#
# Wraps generate-comment.sh + gh to post the never-done audit comment on
# a PR. Idempotent: skips if the audit comment already exists.
#
# Usage:
#   PR_NUMBER=123 OWNER=wave-av REPO=my-repo post-comment.sh
#
# Env contract:
#   PR_NUMBER (required)
#   OWNER     (required)
#   REPO      (required)
#   GH_TOKEN  (required; or `gh` auth in scope)

set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER required}"
: "${OWNER:?OWNER required}"
: "${REPO:?REPO required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Read PR body via gh.
body=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" --jq '.body // ""')

# 2. Idempotency: check existing comments for our sentinel string.
sentinel='Closure audit — invitation, not a blocker'
existing=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
            --jq "[.[] | select(.body | contains(\"$sentinel\"))] | length")

if [ "$existing" -gt 0 ]; then
  echo "never-done: audit comment already present on PR #$PR_NUMBER (skipping)"
  exit 0
fi

# 3. Generate the comment markdown (exit 2 = no closure pattern).
if comment=$(printf '%s' "$body" | bash "$SCRIPT_DIR/generate-comment.sh"); then
  echo "never-done: closure pattern detected on PR #$PR_NUMBER — posting audit comment"
  printf '%s' "$comment" | gh pr comment "$PR_NUMBER" --repo "$OWNER/$REPO" --body-file -
else
  rc=$?
  if [ "$rc" = "2" ]; then
    echo "never-done: no closure pattern on PR #$PR_NUMBER (silent)"
    exit 0
  fi
  echo "never-done: generate-comment.sh failed with rc=$rc"
  exit "$rc"
fi
