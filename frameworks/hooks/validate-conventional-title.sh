#!/usr/bin/env bash
# validate-conventional-title.sh — the ONE source of truth for "is this title valid?".
#
# Mirrors .github/workflows/semantic-pr.yml (amannn/action-semantic-pull-request) EXACTLY so the
# rule that runs in CI is the same rule that runs locally — they can never drift. Wired in three
# places, all calling THIS script:
#   1. local commit-msg hook   → blocks a bad subject before the commit even lands (pre-commit stage)
#   2. gh-pr-create preflight   → `pr-title-preflight.sh` validates --title before the PR exists
#   3. semantic-pr.yml CI       → a parity step runs this against the PR title (belt + suspenders)
# So a title failure is caught AS the work is created, never discovered after the PR is open.
#
# Rules (kept identical to semantic-pr.yml):
#   - Conventional Commits type from @commitlint/config-conventional (the action's default set).
#   - requireScope: false  → scope is optional; if present it's (lower-kebab).
#   - subjectPattern: ^(?![A-Z]).+$  → subject (after ": ") must be non-empty and not start uppercase.
#   - wip: true  → a WIP title (e.g. "WIP: ...", "🚧 ...") passes (work-in-progress escape hatch).
#   - breaking "!" (feat!: / fix(scope)!:) is allowed.
#
# Usage:  validate-conventional-title.sh "<title>"      # arg form
#         echo "<title>" | validate-conventional-title.sh   # stdin form
# Exit:   0 = valid, 1 = invalid (prints the reason + a fix hint to stderr).
set -euo pipefail

# @commitlint/config-conventional types — the amannn action's default when no `types:` is given.
TYPES="build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test"

title="${1:-}"
# Accept three calling conventions, all funnelling to ONE rule:
#   - a literal title string           (preflight / CI parity step)
#   - a path to a commit-msg file      (pre-commit `commit-msg` stage passes $1 = .git/COMMIT_EDITMSG)
#   - the title on stdin               (echo "..." | validate-...)
if [ -n "$title" ] && [ -f "$title" ]; then
  title="$(cat "$title")"
elif [ -z "$title" ] && [ ! -t 0 ]; then
  IFS= read -r title || true
fi
# commit-msg files carry comments/trailers; the title is the first non-empty, non-comment line.
title="$(printf '%s\n' "$title" | sed -n '/^[^#]/{p;q;}' | sed 's/[[:space:]]*$//')"

if [ -z "$title" ]; then
  echo "title-guard: empty title." >&2
  exit 1
fi

fail() {
  {
    echo "title-guard: ✗ \"$title\""
    echo "  $1"
    echo "  expected:  <type>[(scope)][!]: <subject>   (subject must not start with a capital)"
    echo "  types:     ${TYPES//|/, }"
    echo "  examples:  feat(claude-api): add usage standard   ·   fix: handle null token   ·   docs: clarify caching"
    echo "  wip ok:    a title starting with WIP (or 🚧) is allowed for drafts"
  } >&2
  exit 1
}

# wip:true — work-in-progress titles bypass the check (matches the action). Detect a leading
# "WIP" token (any case) or the 🚧 emoji, portably (no \x byte-escapes — BSD grep treats them literally).
first_word="$(printf '%s' "$title" | sed -E 's/[[:space:]:].*$//')"
upper_first="$(printf '%s' "$first_word" | tr '[:lower:]' '[:upper:]')"
case "$title" in
  🚧*) wip=1 ;;
  *) [ "$upper_first" = "WIP" ] && wip=1 || wip=0 ;;
esac
if [ "$wip" = 1 ]; then
  echo "title-guard: ✓ WIP title accepted: \"$title\""
  exit 0
fi

# Must be <type>[(scope)][!]: <subject> with the conventional type set.
if ! printf '%s' "$title" | grep -qE "^(${TYPES})(\([^)]+\))?!?: .+"; then
  fail "not a Conventional Commit — needs a valid '<type>: ' prefix."
fi

# subjectPattern ^(?![A-Z]).+$ — strip "<type>[(scope)][!]: " then check the first subject char.
subject="$(printf '%s' "$title" | sed -E "s/^(${TYPES})(\([^)]+\))?!?: //")"
if [ -z "$subject" ]; then
  fail "subject is empty."
fi
# NOTE: an explicit A..Z set, NOT the range [A-Z] — under most locales' collation order
# (A,a,B,b,...) the range [A-Z] also matches lowercase b-z, which would reject valid titles.
case "$subject" in
  [ABCDEFGHIJKLMNOPQRSTUVWXYZ]*) fail "subject must not start with an uppercase letter (semantic-pr subjectPattern)." ;;
esac

echo "title-guard: ✓ \"$title\""
exit 0
