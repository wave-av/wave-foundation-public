#!/usr/bin/env bash
# Hook: session-start-context.sh
# Trigger: Setup (runs once at session start)
# Purpose: Auto-gather session context so Claude starts with awareness
#          This replaces the need to manually type /session:start

set +e # Don't exit on error - this is a context-gathering hook, not a gate

# Gather all context in parallel
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
UNCOMMITTED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "none")

# Check for handoff
HANDOFF=""
if [[ -f ".claude/state/handoff-latest.md" ]]; then
  HANDOFF_AGE=$(($(date +%s) - $(stat -f %m ".claude/state/handoff-latest.md" 2>/dev/null || stat -c %Y ".claude/state/handoff-latest.md" 2>/dev/null || echo "0")))
  if [[ "$HANDOFF_AGE" -lt 86400 ]]; then
    HANDOFF="Found ($((HANDOFF_AGE / 3600))h ago)"
  fi
fi

# Check for active tasks
TASKS=""
if [[ -f ".claude/state/tasks/active-tasks.json" ]]; then
  TASK_SIZE=$(wc -c <".claude/state/tasks/active-tasks.json" 2>/dev/null || echo "0")
  if [[ "$TASK_SIZE" -gt 10 ]]; then
    TOTAL=$(grep -c '"status"' ".claude/state/tasks/active-tasks.json" 2>/dev/null || echo "0")
    COMPLETED=$(grep -c '"completed"' ".claude/state/tasks/active-tasks.json" 2>/dev/null || echo "0")
    TASKS="$COMPLETED/$TOTAL completed"
  fi
fi

# Parallel API calls — run all network requests simultaneously
umask 077
SS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/session-start-context.XXXXXX")" || exit 0
trap 'rm -rf "$SS_TMP"' EXIT

# PR number
timeout 5 gh pr view --json number --jq '.number' >"$SS_TMP/pr" 2>/dev/null &

# CI health
timeout 5 gh run list --branch staging --status failure --limit 3 --json conclusion >"$SS_TMP/ci" 2>/dev/null &

# Sentry unresolved fatal issues (tokens via stdin to avoid process listing exposure)
if [[ -n "${SENTRY_AUTH_TOKEN:-}" ]]; then
  timeout 5 curl -s --config - >"$SS_TMP/sentry" 2>/dev/null <<EOF &
url = "https://sentry.io/api/0/projects/wave-6b/wave/issues/?query=is:unresolved+level:fatal&limit=3"
header = "Authorization: Bearer ${SENTRY_AUTH_TOKEN}"
EOF
fi

# Pre-fetch org usage for statusline
ADMIN_KEY="${ANTHROPIC_ADMIN_API_KEY:-}"
if [[ -z "$ADMIN_KEY" && -f ".env.local" ]]; then
  ADMIN_KEY=$(grep "ANTHROPIC_ADMIN_API_KEY" .env.local 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
fi
if [[ -n "$ADMIN_KEY" ]]; then
  YESTERDAY=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d "-1 day" +%Y-%m-%d 2>/dev/null || true)
  TODAY=$(date -u +%Y-%m-%d)
  if [[ -n "$YESTERDAY" ]]; then
    timeout 5 curl -s --config - >"$SS_TMP/usage" 2>/dev/null <<EOF &
url = "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=${YESTERDAY}T00:00:00Z&ending_at=${TODAY}T00:00:00Z&bucket_width=1d"
header = "anthropic-version: 2023-06-01"
header = "x-api-key: ${ADMIN_KEY}"
EOF
  fi
fi

wait # Wait for all background API calls

# Read results from temp files
PR_NUM=$(cat "$SS_TMP/pr" 2>/dev/null || echo "")

# Operational context: recent incidents
INCIDENT_COUNT=0
if [[ -f ".claude/memories/incidents/recent-patterns.md" ]]; then
  INCIDENT_COUNT=$(grep -c "^## " ".claude/memories/incidents/recent-patterns.md" 2>/dev/null || echo "0")
fi

CI_HEALTH="healthy"
STAGING_FAILS=$(cat "$SS_TMP/ci" 2>/dev/null | grep -c "failure" || echo "0")
if [[ "$STAGING_FAILS" -gt 0 ]]; then
  CI_HEALTH="${STAGING_FAILS} recent failures"
fi

SENTRY_UNRESOLVED="0"
if [[ -f "$SS_TMP/sentry" ]]; then
  SENTRY_UNRESOLVED=$(grep -c '"id"' "$SS_TMP/sentry" 2>/dev/null || echo "0")
fi

if [[ -f "$SS_TMP/usage" ]]; then
  RESP=$(cat "$SS_TMP/usage")
  if [[ -n "$RESP" && "$RESP" != *"error"* ]]; then
    OUTPUT_TOKENS=$(echo "$RESP" | jq '[.data[0]?.results[]?.output_tokens // 0] | add // 0' 2>/dev/null || echo "0")
    if [[ "$OUTPUT_TOKENS" -gt 0 ]]; then
      DOLLARS=$(echo "scale=0; $OUTPUT_TOKENS * 10 / 1000000" | bc 2>/dev/null || echo "0")
      COST_TMP="$(mktemp "${TMPDIR:-/tmp}/cc-sl-orgcost.XXXXXX")" && printf '%s' "$DOLLARS" >"$COST_TMP" && mv -f "$COST_TMP" /tmp/cc-sl-orgcost-v6
    fi
  fi
fi

# SS_TMP cleanup handled by EXIT trap

# Initialize concern manifest for autonomous PR pipeline
CONCERN_MANIFEST="${TMPDIR:-/tmp/claude}/concern-manifest.json"
mkdir -p "$(dirname "$CONCERN_MANIFEST")"
if [ -f ".claude/config/concern-zones.json" ]; then
  # Pre-populate manifest with already-uncommitted files
  MANIFEST_ZONES='{}'
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    zone="unknown"
    case "$file" in
      supabase/* | */migrations/* | *.sql) zone="database" ;;
      src/types/* | *.d.ts) zone="types" ;;
      src/services/*) zone="service" ;;
      app/api/*) zone="api" ;;
      src/components/* | app/page.tsx) zone="ui" ;;
      app/\(dashboard\)/* | app/\(marketing\)/* | app/\(auth\)/* | app/\(products\)/*) zone="ui" ;;
      packages/*) zone="packages" ;;
      companion-module-wave-av/*) zone="companion" ;;
      app/products/* | .claude/products/*) zone="products" ;;
      scripts/* | .github/* | workers/*) zone="infra" ;;
      .claude/* | *.config.* | .mcp.json | src/config/*) zone="config" ;;
      public/* | apps/*/public/* | *.svg | *.ico | *.png) zone="assets" ;;
      docs/* | *.md) zone="docs" ;;
    esac
    MANIFEST_ZONES=$(echo "$MANIFEST_ZONES" | jq --arg z "$zone" --arg f "$file" \
      '.[$z] = ((.[$z] // []) + [{"file": $f, "ts": "pre-existing"}])' 2>/dev/null || echo "$MANIFEST_ZONES")
  done < <(git status --short 2>/dev/null | awk '{print $2}')

  ZONE_COUNT=$(echo "$MANIFEST_ZONES" | jq 'keys | length' 2>/dev/null || echo "0")
  echo "{\"touched\":$MANIFEST_ZONES,\"last_zone\":\"\",\"zone_count\":$ZONE_COUNT,\"session_start\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >"$CONCERN_MANIFEST"
fi

# Branch divergence check for multi-actor coordination
DIVERGENCE_HINT=""
if [[ "$BRANCH" == feat/* || "$BRANCH" == fix/* || "$BRANCH" == chore/* ]]; then
  git fetch origin staging --quiet 2>/dev/null
  BEHIND_STAGING=$(git rev-list --count "HEAD..origin/staging" 2>/dev/null || echo "0")
  if [[ "$BEHIND_STAGING" -gt 10 ]]; then
    DIVERGENCE_HINT="  ⚠️  Branch is $BEHIND_STAGING commits behind staging — consider rebasing: git rebase origin/staging"
  elif [[ "$BEHIND_STAGING" -gt 5 ]]; then
    DIVERGENCE_HINT="  ℹ️  Branch is $BEHIND_STAGING commits behind staging"
  fi
  # Check for remote changes on this branch (other actors)
  git fetch origin "$BRANCH" --quiet 2>/dev/null
  BEHIND_REMOTE=$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo "0")
  if [[ "$BEHIND_REMOTE" -gt 0 ]]; then
    DIVERGENCE_HINT="$DIVERGENCE_HINT\n  ⚠️  Remote has $BEHIND_REMOTE new commit(s) on $BRANCH — another actor pushed (Cursor bot?). Pull first."
  fi
fi

# Branch workflow awareness
BRANCH_HINT=""
if [[ "$BRANCH" == "staging" ]]; then
  BRANCH_HINT="  ⚠️  On staging — create a feature branch before changes: git checkout -b feat/<description>"
elif [[ "$BRANCH" == "main" ]]; then
  BRANCH_HINT="  ⚠️  On main — switch to staging or create a feature branch first"
elif [[ "$BRANCH" == feat/* || "$BRANCH" == fix/* || "$BRANCH" == chore/* || "$BRANCH" == docs/* ]]; then
  BRANCH_HINT="  ✅ Working on $BRANCH — PR target: staging"
fi

# Build context output
cat <<EOF

SESSION CONTEXT (auto-detected):
  Branch: $BRANCH | Uncommitted: $UNCOMMITTED files | Last: $LAST_COMMIT
${BRANCH_HINT}
$([ -n "$DIVERGENCE_HINT" ] && echo -e "$DIVERGENCE_HINT")
  Handoff: ${HANDOFF:-None}
  Tasks: ${TASKS:-None}
  PR: ${PR_NUM:+#$PR_NUM}${PR_NUM:-None}
  Operational: ${INCIDENT_COUNT} incident patterns | CI: ${CI_HEALTH} | Sentry: ${SENTRY_UNRESOLVED} unresolved fatal

  Available workflows:
  /plan:new, /plan:from-issue, /plan:from-linear, /plan:from-sentry
  /session:start (detailed), /session:standup (daily summary)

EOF

exit 0
