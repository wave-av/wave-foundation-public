#!/usr/bin/env bash
# lint-request-shape.sh — block Claude-API request shapes the standard forbids, at commit time.
#
# This is the gate form of frameworks/claude-api/model-matrix.md. It catches the EXACT bug class the
# whole claude-api standard was built to fix (e.g. temperature sent to Opus 4.8 → HTTP 400) BEFORE the
# code lands, in any spoke — instead of discovering it as a 400 in production.
#
# What it flags (hard fail unless escaped):
#   1. Date-suffixed model IDs        claude-(opus|sonnet|haiku)-N(-N)?-YYYYMMDD   (never append a date)
#   2. Opus 4.7/4.8 + budget_tokens   (budget_tokens fully removed on 4.7/4.8 → 400; use adaptive thinking)
#   3. Opus 4.x + sampling params     temperature / top_p / top_k  (removed on Opus 4.x → 400)
#   4. Haiku 4.5 + effort             (output_config.effort errors on Haiku 4.5)
#   5. Deprecated output_format       (use output_config.format)
#
# Scope + false-positive controls:
#   - Only CODE files (py/ts/tsx/js/jsx/mjs/cjs/go/rb/java/kt/cs/php/sh) — NEVER .md, so the standard's
#     own ❌ anti-pattern docs don't trip it.
#   - Patterns 2-4 only fire in files that look Claude-related (mention anthropic / claude- / messages.create
#     / v1/messages), so a generic `temperature` in non-Claude code is ignored.
#   - Escape hatch: a line with `claude-api-lint: ignore`, or any file containing `claude-api-lint: skip`.
#
# Usage:  lint-request-shape.sh [file ...]      # pre-commit passes changed files
#         lint-request-shape.sh                  # no args → scan git-tracked code files
# Exit:   0 clean, 1 violations found (printed to stderr with file:line + the fix).
set -euo pipefail

CODE_RE='\.(py|ts|tsx|js|jsx|mjs|cjs|go|rb|java|kt|cs|php|sh)$'
DATE_MODEL_RE='claude-(opus|sonnet|haiku)-[0-9]+(-[0-9]+)?-[0-9]{6,8}'
# Provider-namespaced aggregator slug (<vendor>/claude-…): the aggregator's naming may legitimately
# carry a date suffix (OpenRouter `anthropic/claude-haiku-4-5-20251001`). This rule governs
# Anthropic-DIRECT IDs only, so such slugs are stripped before the date-suffix check. The `/` is the tell.
AGG_SLUG_RE='[A-Za-z0-9_.:-]+/claude-(opus|sonnet|haiku)[A-Za-z0-9._-]*'
CLAUDE_RE='anthropic|claude-(opus|sonnet|haiku)|messages\.create|/v1/messages|Anthropic\('
SAMPLING_RE='(^|[^a-zA-Z_])(temperature|top_p|top_k)([^a-zA-Z_]|$)'

# Collect candidate files.
files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
elif git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
fi

violations=0
report() {
  # report <file> <line-no> <message>
  echo "claude-api-lint: ✗ $1:$2" >&2
  echo "    $3" >&2
  violations=$((violations + 1))
}

# grep an ERE in a file, emit a report for each hit not carrying the inline-ignore marker.
# Optional $4 = a strip-ERE removed from the line before the hit is re-confirmed — used so a match
# embedded only in an exempt token (e.g. an aggregator slug) doesn't fire.
flag_lines() {
  local file="$1" pattern="$2" msg="$3" strip="${4:-}" hit lineno text probe
  while IFS= read -r hit; do
    lineno="${hit%%:*}"
    text="${hit#*:}"
    case "$text" in *claude-api-lint:\ ignore*) continue ;; esac
    if [ -n "$strip" ]; then
      probe=$(printf '%s' "$text" | sed -E "s#${strip}##g")
      printf '%s' "$probe" | grep -qE "$pattern" || continue   # match lived only in an exempt token
    fi
    report "$file" "$lineno" "$msg"
  done < <(grep -nE "$pattern" "$file" 2>/dev/null || true)
}

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  printf '%s\n' "$f" | grep -qE "$CODE_RE" || continue
  # Path excludes: honor the repo FIDELITY rule (never rewrite harvested staging/ reference — same
  # set every other hook skips), and don't scan generated/vendored trees or the foundation copy a
  # spoke vendors (which holds this very script + the standard's docs).
  case "$f" in
    staging/* | */node_modules/* | node_modules/* | */dist/* | dist/* | .foundation/* | */vendor/* | vendor/*) continue ;;
  esac
  # file-level skip (e.g. a reference shim that handles these params by design)
  grep -q 'claude-api-lint: skip' "$f" 2>/dev/null && continue

  # 1) date-suffixed model id — always wrong for Anthropic-DIRECT IDs (aggregator slugs are exempt).
  flag_lines "$f" "$DATE_MODEL_RE" "date-suffixed model ID — use the bare ID (e.g. claude-opus-4-8), never append a date." "$AGG_SLUG_RE"

  # patterns 2-5 only in Claude-related files
  grep -qE "$CLAUDE_RE" "$f" 2>/dev/null || continue
  is_opus4=$(grep -qE 'claude-opus-4-' "$f" 2>/dev/null && echo 1 || echo 0)
  is_opus478=$(grep -qE 'claude-opus-4-(7|8)' "$f" 2>/dev/null && echo 1 || echo 0)
  is_haiku45=$(grep -qE 'claude-haiku-4-5' "$f" 2>/dev/null && echo 1 || echo 0)

  if [ "$is_opus478" = 1 ]; then
    flag_lines "$f" '(^|[^a-zA-Z_])budget_tokens([^a-zA-Z_]|$)' \
      "budget_tokens with Opus 4.7/4.8 → 400. Use thinking:{type:'adaptive'} (no budget) + output_config.effort."
  fi
  if [ "$is_opus4" = 1 ]; then
    flag_lines "$f" "$SAMPLING_RE" \
      "temperature/top_p/top_k with Opus 4.x → 400 (sampling params removed). Steer via prompting + effort."
  fi
  if [ "$is_haiku45" = 1 ]; then
    flag_lines "$f" '(^|[^a-zA-Z_])effort([^a-zA-Z_]|$)' \
      "output_config.effort errors on Haiku 4.5 — effort is Sonnet-4.6/Opus-4.5+ only."
  fi
  # 5) deprecated output_format (but NOT output_config.format)
  while IFS= read -r hit; do
    lineno="${hit%%:*}"
    text="${hit#*:}"
    case "$text" in *output_config*) continue ;; esac
    case "$text" in *claude-api-lint:\ ignore*) continue ;; esac
    report "$f" "$lineno" "output_format is deprecated — use output_config:{format:{...}} on messages.create()."
  done < <(grep -nE '(^|[^a-zA-Z_.])output_format([^a-zA-Z_]|$)' "$f" 2>/dev/null || true)
done

if [ "$violations" -gt 0 ]; then
  echo "claude-api-lint: $violations violation(s). See frameworks/claude-api/model-matrix.md. Escape a deliberate case with 'claude-api-lint: ignore' on the line." >&2
  exit 1
fi
echo "claude-api-lint: ✓ no forbidden Claude-API request shapes"
exit 0
