#!/usr/bin/env bash
#
# revoke-on-edit.sh — when an issue is EDITED, revoke any prior agent approval so
# a human must re-approve the NEW content before Stage C can act on it.
#
# Closes the approve-then-edit race (security audit 2026-05-31, insider lens):
# without this, a maintainer could approve benign text v1, an attacker edits the
# body to hostile text v2, and a re-label would run the code-writing agent on v2.
# By stripping agent:approved (and agent:go) on every edit, the approval no longer
# carries across a content change — re-approval is required, and the human sees v2.
#
# (Why this is sufficient without a separate body-hash pin: Stage C reads the issue
# body from the triggering event payload — an atomic snapshot at label time — and
# re-labeling now requires a write-access approver (verify-approver.sh). Auto-revoke
# on edit + that approver check together close the race; a hash pin would be
# redundant with the event-payload read.)
#
# Idempotent: removes only labels that are present; comments only if it removed
# something. Fail-soft on individual gh calls so a transient hiccup never wedges
# triage, but reports a non-zero exit if it could not read the labels at all.
#
# Env: ISSUE_NUMBER (required), REPO (default wave-av/wave-foundation), GH_TOKEN.
set -euo pipefail

ISSUE_NUMBER="${ISSUE_NUMBER:-}"
REPO="${REPO:-wave-av/wave-foundation}"

[ -n "$ISSUE_NUMBER" ] || { echo "revoke-on-edit: ISSUE_NUMBER is required" >&2; exit 1; }

labels="$(gh issue view "$ISSUE_NUMBER" -R "$REPO" --json labels --jq '.labels[].name' 2>/dev/null)" || {
  echo "revoke-on-edit: could not read labels for #$ISSUE_NUMBER" >&2
  exit 1
}

removed=0
for lbl in "agent:approved" "agent:go"; do
  if printf '%s\n' "$labels" | grep -qxF "$lbl"; then
    gh issue edit "$ISSUE_NUMBER" -R "$REPO" --remove-label "$lbl" >/dev/null 2>&1 || true
    removed=1
  fi
done

if [ "$removed" -eq 1 ]; then
  gh issue comment "$ISSUE_NUMBER" -R "$REPO" --body \
    "⚠️ Agent approval auto-revoked: this issue was edited after it was approved. Re-apply \`agent:approved\` to act on the **new** content (approve-then-edit guard)." \
    >/dev/null 2>&1 || true
  echo "revoked"
else
  echo "noop"
fi
