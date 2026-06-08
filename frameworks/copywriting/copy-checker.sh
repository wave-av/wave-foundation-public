#!/usr/bin/env bash
# WAVE copywriting gate — enforce the voice-and-tone standard on user-facing copy.
# Usage:
#   copy-checker.sh <file...>     # check specific files
#   copy-checker.sh --staged      # check staged user-facing files (lefthook / pre-commit)
#   copy-checker.sh --changed     # check files changed vs origin default branch (CI)
# Exit 1 if any ERROR-severity violation is found; WARN-severity prints but does not fail.
set -uo pipefail

# User-facing surfaces only (prose), not code/specs/machine docs. The copywriting framework itself
# (this standard + its fixtures) legitimately discusses "human" as a concept, so it's exempt.
is_target() { case "$1" in
  *frameworks/copywriting/*|*voice-and-tone*) return 1 ;;
  *.tsx|*.ts|*.md|*.mdx|*landing*|*shell*|*nav*|*pages*) [[ "$1" != *.test.* && "$1" != *.spec.* ]] ;;
  *) return 1 ;;
esac; }

collect() {
  case "${1:-}" in
    --staged)  git diff --cached --name-only --diff-filter=ACM ;;
    --changed) base=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p'); git diff --name-only "origin/${base:-main}...HEAD" ;;
    *) printf '%s\n' "$@" ;;
  esac
}

errors=0; warns=0
report() { # severity file msg
  if [ "$1" = ERROR ]; then errors=$((errors+1)); printf '  ✗ [%s] %s — %s\n' "$1" "$2" "$3"
  else warns=$((warns+1)); printf '  ⚠ [%s] %s — %s\n' "$1" "$2" "$3"; fi
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  is_target "$f" || continue
  # ERROR severity — fail the gate
  grep -qiE 'click here' "$f"           && report ERROR "$f" "'click here' — use descriptive link text"
  grep -qiE '\b(whitelist|blacklist)\b' "$f" && report ERROR "$f" "non-inclusive term — use allowlist/blocklist"
  grep -qE '\bmaster/slave\b' "$f"      && report ERROR "$f" "non-inclusive term — use primary/replica"
  grep -qiE "don'?t miss out|limited time|act now|sign up now!" "$f" && report ERROR "$f" "salesy/urgency copy — forbidden"
  grep -qiE 'something went wrong' "$f" && report ERROR "$f" "vague error — use [what happened]. [how to fix]."
  # ERROR severity — meta-copy: internal strategy/notes-to-us that must never ship as public copy.
  # Only the unambiguous memo phrases (never legitimate in customer prose) are gated fleet-wide;
  # generic dev markers (TODO/Note:) are intentionally NOT here — they're valid in technical docs.
  # (apex wave-www additionally runs scripts/check-meta-copy.mjs, scoped to its marketing files.)
  grep -qiE 'not the headline|labeled honestly|labeled, not implied|truthful by construction|notes? to (us|self|ourselves)' "$f" \
    && report ERROR "$f" "meta-copy — internal note/strategy memo leaking into public copy"
  # Voice: "people"/second person, not "humans" (voice-and-tone.md §human⇄agent taxonomy). Flags
  # user-facing "human/humans" EXCEPT: the "no human in the loop" idiom; the GDPR / EU-AI-Act legal
  # terms "human review"/"human oversight"; the "human-readable" technical term; typography words
  # (humanist/humanize); identifiers/const/id-slugs (HUMANS_*, *-humans-*, "human", .human); and code
  # comment lines (//, *, #, <!--). grep -n prefixes "NN:" so the comment skip anchors on that.
  if grep -niE '\bhumans?\b' "$f" \
       | grep -vE '^[0-9]+:[[:space:]]*(//|\*|#|/\*|<!--)' \
       | grep -qivE 'no human.?in.?the.?loop|human review|human oversight|human-read|humanis|humaniz|HUMANS?_|_HUMANS?|-humans?-|"human"|\.human\b'; then
    report ERROR "$f" "'human/humans' in marketing copy — use 'people' or second person (voice-and-tone.md)"
  fi
  # WARN severity — buzzwords / unsubstantiated (review, don't block)
  grep -qiE '\b(seamless|revolutionary|cutting[- ]edge|next[- ]gen|world[- ]class|game[- ]changer|synergy|leverage|best[- ]in[- ]class)\b' "$f" \
    && report WARN "$f" "buzzword — replace with a specific, substantiated claim"
  grep -qE '\bWave\b' "$f"              && report WARN "$f" "title-case 'Wave' — brand is WAVE (caps) in prose; lowercase 'wave' only as the logotype"
done < <(collect "$@")

echo "—"
if [ "$errors" -gt 0 ]; then
  echo "copywriting gate: $errors error(s), $warns warning(s) → FAIL"
  echo "see frameworks/copywriting/voice-and-tone.md"
  exit 1
fi
echo "copywriting gate: 0 errors, $warns warning(s) → PASS"
exit 0
