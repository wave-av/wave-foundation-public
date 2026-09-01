#!/usr/bin/env bash
# triage.sh — Stage A. Deterministic, no LLM.
# Env: ISSUE_NUMBER AUTHOR ASSOC BODY [REPO]
# Applies trust + category labels; parks outsiders; flags spam.
# Prints final state: triaged | parked | spam
set -euo pipefail
d="$(dirname "$0")"
# shellcheck source=scripts/issue-ops/lib.sh
source "$d/lib.sh"

: "${ISSUE_NUMBER:?}"
: "${AUTHOR:?}"
BODY="${BODY:-}"
REPO="${REPO:-wave-av/wave-foundation}"

cat="$(printf '%s' "$BODY" | "$d/classify.sh")"
tier="$("$d/trust-tier.sh" "$AUTHOR" "${ASSOC:-NONE}")"

# Apply a label, self-healing the label set on first use in a freshly-enrolled repo.
# gh refuses to add a label that doesn't exist ("'trust:owner' not found"). On a repo
# that never ran sync-labels.sh that used to kill triage mid-run with a cryptic error
# (the #1 latent break for the org fan-out). Instead: try; on failure bootstrap the full
# issue-ops label set once (needs only issues:write, already held) and retry; if it STILL
# fails, exit with an actionable message instead of gh's opaque one. On wave-foundation —
# and any repo whose labels already exist — the first add succeeds and this is a no-op.
label() {
  gh issue edit "$ISSUE_NUMBER" -R "$REPO" --add-label "$1" >/dev/null 2>&1 && return 0
  REPO="$REPO" "$d/sync-labels.sh" >/dev/null 2>&1 || true
  gh issue edit "$ISSUE_NUMBER" -R "$REPO" --add-label "$1" >/dev/null 2>&1 && return 0
  echo "::error::triage could not apply label '$1' to #$ISSUE_NUMBER in $REPO. The issue-ops labels are missing and auto-sync failed (token lacks label write?). Run: REPO=$REPO bash scripts/issue-ops/sync-labels.sh" >&2
  exit 1
}

label "trust:$tier"
label "category:$cat"

if [ "$cat" = "spam" ]; then
  label "needs-human-review"
  echo "spam"
  exit 0
fi

if [ "$tier" = "outside" ]; then
  label "needs-human-ack"
  echo "parked"
  exit 0
fi

# Dedup against other OPEN issues (fail-soft — never blocks triage).
title="$(gh issue view "$ISSUE_NUMBER" -R "$REPO" --json title --jq .title 2>/dev/null || true)"
if [ -n "$title" ]; then
  others="$(gh issue list -R "$REPO" --state open --json number,title \
    --jq '.[] | [.number, .title] | @tsv' 2>/dev/null \
    | awk -F'\t' -v cur="$ISSUE_NUMBER" '$1 != cur' || true)"
  dup="$(printf '%s\n' "$others" | "$d/dedup.sh" "$title" 2>/dev/null || true)"
  if [ -n "$dup" ]; then
    gh issue comment "$ISSUE_NUMBER" -R "$REPO" \
      --body "Possible duplicate of #${dup}." >/dev/null 2>&1 || true
    gh issue edit "$ISSUE_NUMBER" -R "$REPO" \
      --add-label "possible-duplicate" >/dev/null 2>&1 || true
  fi
fi

echo "triaged"
