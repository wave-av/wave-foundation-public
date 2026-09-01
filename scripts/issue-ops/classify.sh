#!/usr/bin/env bash
# classify.sh — read issue body on stdin, print category. Deterministic, no LLM.
# Categories: bug | feature | idea | question | spam
set -euo pipefail

body="$(cat)"

# Authoritative: explicit template marker. Capture any case, then lowercase
# the value so `Bug`/`FEATURE`/`Idea` are honored (issue #198).
marker="$(printf '%s' "$body" | sed -nE 's/.*issue-ops:category=([A-Za-z]+).*/\1/p' | head -1 | tr '[:upper:]' '[:lower:]')"
case "$marker" in
  bug | feature | idea | question)
    printf '%s' "$marker"
    exit 0
    ;;
esac

# Heuristic fallback for marker-less issues (legacy / API-created).
lc="$(printf '%s' "$body" | tr '[:upper:]' '[:lower:]')"
links="$(printf '%s' "$lc" | { grep -oE 'https?://' || true; } | wc -l | tr -d ' ')"
words="$(printf '%s' "$lc" | wc -w | tr -d ' ')"
if [ "$links" -ge 1 ] && [ "$words" -le 6 ]; then
  printf 'spam'
  exit 0
fi
case "$lc" in
  *error* | *crash* | *broken* | *fail*) printf 'bug' ;;
  *) printf 'question' ;;
esac
