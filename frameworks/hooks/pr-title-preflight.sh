#!/usr/bin/env bash
# pr-title-preflight.sh — validate a PR title BEFORE `gh pr create`, so semantic-pr never goes red.
#
# The PR-title check (semantic-pr.yml) only runs once the PR exists on GitHub — by then a bad title
# is already a red X. This runs the SAME rule (validate-conventional-title.sh) locally, first.
#
# Usage:
#   bash pr-title-preflight.sh "feat(scope): do the thing"   # then, if it passes, gh pr create
#   # or use the wrapper to do both in one shot:
#   bash pr-title-preflight.sh --create "feat(scope): do the thing" [extra gh pr create args...]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$HERE/validate-conventional-title.sh"

mode="check"
if [ "${1:-}" = "--create" ]; then
  mode="create"
  shift
fi

title="${1:-}"
shift || true
if [ -z "$title" ]; then
  echo "usage: pr-title-preflight.sh [--create] \"<pr title>\" [gh pr create args...]" >&2
  exit 2
fi

# One rule, one source: the same validator CI and the commit-msg hook use.
bash "$VALIDATOR" "$title"

if [ "$mode" = "create" ]; then
  echo "title-guard: title ok → gh pr create"
  exec gh pr create --title "$title" "$@"
fi
