#!/usr/bin/env bash
# Hook: shared-checkout-claim — detects when another active session has claimed the same git
# checkout, and warns prominently. Event: SessionStart.
#
# WHY: the 2026-05-28 incident — concurrent sessions on the SAME checkout, one ran a destructive
# git op while the other had in-progress work; commits orphaned, working tree wiped. The
# git-safety-guard hook blocks the destructive ops in agent Bash, but it doesn't tell you in
# advance "another agent is here, branch out". This hook does.
#
# Mechanism: each session writes a claim file
#   $HOME/.wave-foundation-sessions/<sha-of-cwd>/<pid>.claim
# at SessionStart with: pid, cwd, branch, timestamp. On start, list peers (same dir hash,
# different pid). If any are alive (kill -0), warn loud + suggest `git worktree add`.
#
# Stale claims (process gone) are auto-cleaned. The fingerprint is the resolved cwd, so this
# detects shared CHECKOUT — separate worktrees of the same repo have different cwds and don't
# collide (which is exactly the intent).

set +e

cwd_real="$(cd "$PWD" 2>/dev/null && pwd -P)" || exit 0
[ -d "$cwd_real/.git" ] || git -C "$cwd_real" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Linked worktree? Skip — that IS the recommended pattern; no collision.
common_dir=$(git -C "$cwd_real" rev-parse --git-common-dir 2>/dev/null)
git_dir=$(git -C "$cwd_real" rev-parse --git-dir 2>/dev/null)
if [ -n "$common_dir" ] && [ -n "$git_dir" ] && [ "$common_dir" != "$git_dir" ]; then
  exit 0
fi

cwd_hash=$(printf '%s' "$cwd_real" | shasum | cut -c1-12)
claims_dir="$HOME/.wave-foundation-sessions/$cwd_hash"
mkdir -p "$claims_dir" 2>/dev/null

# Stamp our own claim first (so concurrent peers see us too).
my_pid=$$
my_claim="$claims_dir/${my_pid}.claim"
branch=$(git -C "$cwd_real" symbolic-ref --short HEAD 2>/dev/null || echo "detached")
{
  echo "pid=$my_pid"
  echo "cwd=$cwd_real"
  echo "branch=$branch"
  echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$my_claim" 2>/dev/null

# Find peers; clean stale (dead pid) along the way.
peers=()
shopt -s nullglob
for f in "$claims_dir"/*.claim; do
  pid=$(basename "$f" .claim)
  [ "$pid" = "$my_pid" ] && continue
  if kill -0 "$pid" 2>/dev/null; then
    peers+=("$f")
  else
    rm -f "$f" 2>/dev/null
  fi
done

if [ ${#peers[@]} -gt 0 ]; then
  cat <<EOF >&2

══════════════════════════════════════════════════════════════════════
⚠ SHARED CHECKOUT DETECTED — $cwd_real
══════════════════════════════════════════════════════════════════════

Another active Claude Code session is claimed on this same checkout:

EOF
  for f in "${peers[@]}"; do
    pid=$(basename "$f" .claim)
    branch_p=$(grep '^branch=' "$f" 2>/dev/null | cut -d= -f2)
    started_p=$(grep '^started=' "$f" 2>/dev/null | cut -d= -f2)
    echo "  pid=$pid  branch=$branch_p  since=$started_p" >&2
  done
  cat <<EOF >&2

A second session writing the same working tree is the root cause of the
2026-05-28 incident (orphaned commits + wiped working tree).

→ Recommended: branch out into a worktree so both sessions can work safely:
    cd ~/wave-foundation
    git worktree add ../wave-foundation-\$(date +%s) -b feat/your-task

The agent git-safety-guard.sh will still block destructive ops in this
session, but the warning above is the cheaper fix. See rules/git-workflow.md
and rules/shared-checkout-prevention.md.

══════════════════════════════════════════════════════════════════════

EOF
fi

exit 0
