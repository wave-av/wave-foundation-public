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
  # user-facing "human/humans" EXCEPT: the "human-in-the-loop" term-of-art (HITL — an approval step, like
  # "human review"; covers the "no human in the loop" autonomy idiom too); the GDPR / EU-AI-Act legal
  # terms "human review"/"human oversight"; the "human-readable" technical term; typography words
  # (humanist/humanize); identifiers/const/id-slugs (HUMANS_*, *-humans-*, "human", .human, and the
  # specific enumerated identifier human[-_]resources — see below); code
  # comment lines (//, *, #, <!--); and markdown backticked code spans (`async-human`), which are
  # blanked BEFORE matching, in MARKDOWN ONLY — identifiers quoted verbatim from source are not
  # marketing copy. In .ts/.tsx a backtick delimits a TEMPLATE LITERAL, whose contents are
  # frequently real user-facing copy, so source files keep the raw text. An unbalanced backtick
  # strips nothing, so residue fails CLOSED. grep -n prefixes "NN:" so the comment skip anchors
  # on that.
  # KEEP THIS ALLOWLIST IN SYNC with the .github/workflows/checks.yml "voice" job (same regexes +
  # the same markdown-only code-span blanking, two enforcers; CI additionally narrows to PR-ADDED
  # lines, which commit-time cannot — staged hunks are the local analogue of "added", and
  # whole-file here is the stricter, pre-existing behavior).
  # shellcheck disable=SC2016  # literal markdown code-span delimiters, not command substitution.
  case "$f" in *.md|*.mdx) span='s/`[^`]*`/ /g' ;; *) span='' ;; esac
  # CAPTURE the matches and test non-empty rather than ending the pipeline in `grep -q`: under
  # `set -o pipefail` (line 8), -q exits at the FIRST surviving line, and on a file large enough
  # that upstream stages still have output pending (>64KB pipe buffer) sed/grep die of SIGPIPE
  # (141) — the pipeline status becomes 141 despite the match, the `if` never fires, and a real
  # violation passes silently. The `|| true` guards only the no-match exit 1 (the happy path);
  # mirrors the CI twin, which captures for the same reason.
  # human[-_]resources is an ENUMERATED IDENTIFIER, not a pattern: a hyphen alone cannot distinguish
  # an identifier (human-resources, a plugin-category name) from a compound ADJECTIVE
  # (human-centered, human-first, human-scale — exactly the prose this gate exists to catch). A
  # general "human followed by -/_ " arm let all three of those through silently (measured:
  # wave-foundation PR #1147 review) — that false negative is more expensive on a copy gate than
  # the false positive it was chasing, so widen the allowlist by naming the specific known
  # identifier rather than by generalizing the pattern.
  # claude-workstation#2109: internal engineering plans/epics are not marketing prose — there
  # "human" is the PRECISE word, contrasted with crawler/bot. VOICE RULE ONLY: is_target above
  # deliberately does NOT carve this tree out, so every other ERROR/WARN rule (non-inclusive
  # terms, click-here, urgency, vague errors, meta-copy, buzzwords) still grades plan docs.
  # That is scope-parity with the checks.yml "voice" job, whose ONLY rule is this scan — its
  # whole-file exemption disables exactly one rule, and so does this guard.
  # ANCHORED, not `*governance/plans/*` (see checks.yml): --staged/--changed paths are
  # repo-relative, so a customer-facing `marketing/site/governance/plans/` cannot opt out by
  # directory name.
  # SCOPE-PARITY with checks.yml's voice job (cw#2847): research prose and the READMEs of
  # internal governance tooling carry the same ruling as plans — "human" there is the precise
  # word. The two checkers must exempt the SAME set, or a writer passes CI and is blocked at
  # commit time by this file grading what CI does not (Devin/Qodo finding on the PR adding this).
  if [[ "$f" != governance/plans/* && "$f" != governance/research/* && "$f" != governance/tools/*/README.md ]]; then
    hits=$(sed "$span" "$f" | grep -niE '\bhumans?\b' \
         | grep -vE '^[0-9]+:[[:space:]]*(//|\*|#|/\*|<!--)' \
         | grep -ivE 'human.?in.?the.?loop|human review|human oversight|human-read|humanis|humaniz|HUMANS?_|_HUMANS?|[-_]humans?\b|human[-_]resources\b|"human"|\.human\b' || true)
    if [ -n "$hits" ]; then
      report ERROR "$f" "'human/humans' in marketing copy — use 'people' or second person (voice-and-tone.md)"
    fi
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
