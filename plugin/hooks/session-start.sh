#!/usr/bin/env bash
# wave-foundation session start — remind about key rules, check for stale state,
# and warn about the shared-checkout hazard that caused the 2026-05-28 reset incident.
set +e

# --- post-compaction sentinel (CCCR) ---
# SessionStart fires with source=compact right after a /compact, BEFORE the first post-compact
# prompt. At that instant the transcript's last usage record is still the big PRE-compact value, so
# context-budget-warn.sh would emit a false "approaching the band" warning. Drop a one-shot,
# session-keyed marker that the decision engine consumes to stay quiet for exactly that one turn.
_ss_in="$(cat 2>/dev/null)"
_ss_src="$(printf '%s' "$_ss_in" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("source") or "")
except Exception: print("")' 2>/dev/null)"
if [ "$_ss_src" = "compact" ]; then
  _ss_sid="$(printf '%s' "$_ss_in" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("session_id") or "")
except Exception: print("")' 2>/dev/null)"
  if [ -n "$_ss_sid" ]; then
    mkdir -p /tmp/claude/session-state 2>/dev/null
    : >"/tmp/claude/session-state/postcompact-$_ss_sid" 2>/dev/null
  fi
fi

# Print brief reminder only if interactive (not in CI)
if [ -t 1 ] || [ "${CLAUDE_SESSION_ID:-}" != "" ]; then
  echo "[wave-foundation] Rules loaded: no-mock-data · oklch-colors · rls-policies · behavioral-rules · git-safety"
  echo "[wave-foundation] Skills: /plan-generate /plan-enhance /plan-to-action /plan-audit"
fi

# Check for supabase prod guard
if ! grep -q "supabase-prod-guard" "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/settings.json" 2>/dev/null; then
  echo "[wave-foundation] ⚠️  supabase-prod-guard not wired in project settings.json"
fi

# --- shared-checkout guard (root cause of the 2026-05-28 orphaned-commits incident) ---
# Two agent sessions sharing ONE working tree is the hazard: a reset/checkout/rebase in one
# stomps the other's tree. Detect multiple worktrees and steer each session into its own.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  wt_count=$(git worktree list 2>/dev/null | grep -c .)
  if [ "${wt_count:-0}" -gt 1 ]; then
    echo "[wave-foundation] ⚠️  ${wt_count} worktrees on this repo — a concurrent session may be active."
    echo "                  Work in YOUR OWN worktree, never reset/rebase/checkout a shared one:"
    echo "                    git worktree add ../wf-<task> -b feat/<task> origin/master"
    echo "                  (git reset --hard / push --force / rebase on a shared tree are blocked by git-safety-guard.)"
  fi
  # report the recovery anchor for this branch, if the anchor hook has stamped one
  br=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ -n "$br" ] && git rev-parse --verify --quiet "refs/heads/wip/anchor/${br}" >/dev/null 2>&1; then
    echo "[wave-foundation] recovery anchor: wip/anchor/${br} (in-progress commits stay reachable here)"
  fi
fi

exit 0
