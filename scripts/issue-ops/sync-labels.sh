#!/usr/bin/env bash
#
# sync-labels.sh  — create/update the issue-ops labels in a repo (enrollment prerequisite).
#
# Triage applies trust:/risk:/agent:/needs-human-/category: labels; gh refuses to add a
# label that doesn't exist ("'trust:owner' not found"), so every enrolled consumer repo
# must carry this set BEFORE its first issue. Idempotent (gh label create --force).
#
#   REPO=owner/name bash scripts/issue-ops/sync-labels.sh        # apply
#   DRY_RUN=1 bash scripts/issue-ops/sync-labels.sh              # print only
#
# Keep this set in sync with the "Issue-ops:" section of .github/labels.yml.
set -euo pipefail

# name|color|description  (the issue-ops labels triage/assess/action rely on)
LABELS=(
  "trust:owner|5319e7|Issue author is repo owner"
  "trust:member|5319e7|Issue author is org member/collaborator"
  "trust:outside|5319e7|Issue author is outside/first-time contributor"
  "risk:trivial|c2e0c6|Docs/typo/safe — may skip audit fan-out"
  "risk:standard|fbca04|Code change — full audit fan-out"
  "risk:sensitive|d93f0b|Security/public-surface — full audit + human review"
  "agent:assessed|0052cc|Stage B complete; verdict posted"
  "agent:approved|0e8a16|Human approved; Stage C may act"
  "agent:go|0e8a16|Explicit go for outside-author issue"
  "needs-human-ack|b60205|Outside/first-timer — parked for human ack"
  "needs-human-review|b60205|An auditor flagged this — human must review"
  "category:bug|d73a4a|Something is broken"
  "category:feature|a2eeef|New capability request"
  "category:idea|a2eeef|Idea / improvement to consider"
  "category:question|d876e3|A question, not actionable work"
  "category:spam|000000|Spam / abuse"
  "possible-duplicate|cfd3d7|Triage flagged a likely duplicate of another open issue"
)

repo="${REPO:?set REPO=owner/name}"
n=0
for e in "${LABELS[@]}"; do
  IFS='|' read -r name color desc <<<"$e"
  if [ -n "${DRY_RUN:-}" ]; then
    echo "would sync: $name ($color)"
  else
    gh label create "$name" -R "$repo" --color "$color" --description "$desc" --force >/dev/null
    echo "synced: $name"
  fi
  n=$((n + 1))
done
echo "issue-ops labels: $n ${DRY_RUN:+(dry-run) }-> $repo"
