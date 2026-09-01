#!/usr/bin/env bash
# dedup.sh <candidate-title>
# Reads existing "number<TAB>title" lines on stdin.
# Prints the number of the best match when Jaccard token overlap >= 0.6, else empty.
set -euo pipefail

norm() {
  # Lowercase -> one token per line -> drop stopwords -> light stem (plural/3rd-person)
  # so "crashes" and "crash" match -> dedupe.
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    tr -cs 'a-z0-9' '\n' |
    grep -vE '^(the|a|an|to|of|in|on|is|fix|add)$' |
    sed -E 's/(ies|es|s)$//' |
    sort -u
}

cand="$(norm "${1:?title required}")"
cn=$(printf '%s\n' "$cand" | grep -c . || true)

best=""
bestscore=0
while IFS=$'\t' read -r num title; do
  [ -z "${num:-}" ] && continue
  ex="$(norm "$title")"
  en=$(printf '%s\n' "$ex" | grep -c . || true)
  inter=$(comm -12 <(printf '%s\n' "$cand") <(printf '%s\n' "$ex") | grep -c . || true)
  union=$((cn + en - inter))
  [ "$union" -eq 0 ] && continue
  score=$((inter * 100 / union))
  if [ "$score" -gt "$bestscore" ] && [ "$score" -ge 60 ]; then
    bestscore=$score
    best=$num
  fi
done

printf '%s' "$best"
