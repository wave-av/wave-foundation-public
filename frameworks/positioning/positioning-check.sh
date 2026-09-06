#!/usr/bin/env bash
# WAVE positioning gate — enforce the identity SSOT (frameworks/positioning/positioning.ts) on
# user-facing copy. Twin of the copywriting gate; guards IDENTITY, not voice or claims.
# Usage:
#   positioning-check.sh <file...>     # check specific files
#   positioning-check.sh --staged      # staged user-facing files (lefthook / pre-commit)
#   positioning-check.sh --changed     # files changed vs origin default branch (CI)
# Exit 1 if any ERROR-severity violation is found; WARN-severity prints but does not fail.
set -uo pipefail

# User-facing surfaces only (prose/marketing), not code/specs/machine docs/this framework itself.
is_target() { case "$1" in
  frameworks/positioning/*) return 1 ;;            # never lint the SSOT against itself
  packages/messaging/*) return 1 ;;                 # the published mirror defines the forbidden patterns verbatim
  *.test.*|*.spec.*) return 1 ;;
  *.tsx|*.ts|*.md|*.mdx|*landing*|*shell*|*nav*|*pages*|*copy*|*content*) return 0 ;;
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
  # ERROR — identity drift. "The Agent Money OS" as a brand/tagline is the demoted #627 over-rotation.
  grep -qiE 'the agent money os' "$f"   && report ERROR "$f" "'The Agent Money OS' as a headline — WAVE IS media infrastructure; 'agent money OS' is the lowercase engine descriptor, never the brand. See frameworks/positioning."
  grep -qE '\bMoney OS\b' "$f"           && report ERROR "$f" "'Money OS' — use 'WAVE Money Engine' (engine) / 'WAVE Wallet' (product)."
  # ERROR — the superseded 2026-06-06 identity. Media is the identity (2026-09-02); video is a capability inside it.
  grep -qiE 'video infrastructure for the agentic internet' "$f" \
    && report ERROR "$f" "'video infrastructure for the agentic internet' is superseded — use 'Media infrastructure for the agentic internet.' (POSITIONING.tagline)."
  # ERROR — a capability asserted as the identity ("WAVE is a video API"). Lead with the infrastructure frame.
  grep -qiE '\bWAVE is (a |an |the )?(video|transcription|streaming|captions?) (API|platform|service)\b' "$f" \
    && report ERROR "$f" "a capability is not the identity — lead with 'media infrastructure for the agentic internet'; name the capability beneath it (POSITIONING.capabilities.rule)."
  # ERROR — truth law: WAVE holds no SOC 2 attestation. Vendor attribution (Cloudflare/Supabase/Stripe, 'Type II infrastructure', subprocessor rows) is allowed.
  grep -iE 'SOC ?2' "$f" | grep -qviE 'cloudflare|supabase|stripe|vendor|subprocessor|type ii|no soc 2|not soc 2|never say|never claim|for wave itself' \
    && report ERROR "$f" "SOC 2 stated without vendor attribution — WAVE holds no SOC 2 attestation; attribute vendors or cut."
  # WARN — truth law: no 'first on x402' class claim (every capability is x402-payable; 'first' is unverified).
  grep -qiE '\bfirst\b[^.]{0,30}\bx402\b|\bx402\b[^.]{0,30}\bfirst\b' "$f" \
    && report WARN "$f" "'first' near 'x402' — no 'first on x402' claims; say every capability is x402-payable."
  # ERROR — asserting the Wallet as a shipped product before it is built (truthfulness + positioning).
  grep -qiE '(wave wallet|wallet\.wave\.online)[^.]{0,40}(available|launched|live now|sign up|get started)' "$f" \
    && report ERROR "$f" "WAVE Wallet asserted as available — it is 'planned' (see positioning.ts + copywriting/claims.ts). Do not assert until built."
  # WARN — money-first headline framing that buries the media-infrastructure identity (review, don't block).
  grep -qiE '^\s*(#|kicker|tagline|headline).*(agent (money|commerce|payment) (os|platform|layer))' "$f" \
    && report WARN "$f" "money-first headline — lead with the media-infrastructure identity; payments differentiate. See positioning.ts."
  # WARN — capability-first headline ("video API" / "transcription API" / "streaming platform" as the h1/tagline).
  grep -qiE '^\s*(#\s|kicker|tagline|headline|title)[^\n]*\b(video|transcription|streaming) (api|platform)\b' "$f" \
    && report WARN "$f" "capability-first headline — lead with 'media infrastructure for the agentic internet'; list the capability beneath it."
done < <(collect "$@")

echo "—"
if [ "$errors" -gt 0 ]; then
  echo "positioning gate: $errors error(s), $warns warning(s) → FAIL"
  echo "see frameworks/positioning/README.md"
  exit 1
fi
echo "positioning gate: 0 errors, $warns warning(s) → PASS"
exit 0
