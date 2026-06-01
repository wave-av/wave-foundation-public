#!/usr/bin/env bash
# check-model-strings.sh — block date-suffixed Claude model IDs across CODE *and* CONFIG files.
#
# lint-request-shape.sh catches date-suffixed IDs in code; this extends the same rule to json/yaml
# config (wrangler vars, env templates, model maps) where a stale pinned ID also silently breaks.
# The bare IDs (claude-opus-4-8 etc.) are correct; appending a date (claude-sonnet-4-6-20251114) is  # claude-api-lint: ignore
# the anti-pattern — the skill is explicit that the bare strings are complete as-is.
#
# SCOPE: this rule governs ANTHROPIC-DIRECT model IDs only. Provider-namespaced AGGREGATOR slugs
# (`anthropic/claude-…`, `openrouter:anthropic/claude-…`, `together/…`) follow the AGGREGATOR's
# published naming — which legitimately includes date suffixes — so a `<vendor>/claude-…` token is
# stripped before the check (e.g. champions.json `fallback: anthropic/claude-haiku-4-5-20251001` is a
# valid OpenRouter slug, NOT an Anthropic-direct violation). The `/` is the tell: a direct ID never has one.
#
# Args: file paths (pre-commit passes staged matching files); no args → scan git-tracked files.
# Escape a deliberate case with `claude-api-lint: ignore` on the line. Exit 1 on any hit.
set -euo pipefail

DATE_MODEL_RE='claude-(opus|sonnet|haiku)-[0-9]+(-[0-9]+)?-[0-9]{6,8}'
# Provider-namespaced aggregator slug: <vendor>/claude-… — governed by the aggregator, not this rule.
AGG_SLUG_RE='[A-Za-z0-9_.:-]+/claude-(opus|sonnet|haiku)[A-Za-z0-9._-]*'
# Self-filter to the intended extensions even when handed arbitrary args, so the standard's own .md
# anti-pattern examples never trip (same reason lint-request-shape.sh scans code only, never .md).
EXT_RE='\.(py|ts|tsx|js|jsx|mjs|cjs|go|rb|java|kt|cs|php|sh|json|ya?ml)$'

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
fi

fail=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  printf '%s\n' "$f" | grep -qE "$EXT_RE" || continue
  case "$f" in staging/* | */node_modules/* | node_modules/* | */dist/* | dist/* | .foundation/*) continue ;; esac
  while IFS= read -r hit; do
    case "$hit" in *claude-api-lint:\ ignore*) continue ;; esac
    # Strip provider-namespaced aggregator slugs, then re-test: only an Anthropic-DIRECT date-suffixed
    # ID survives (a `<vendor>/claude-…` token is the aggregator's business, not ours).
    stripped=$(printf '%s' "$hit" | sed -E "s#${AGG_SLUG_RE}##g")
    printf '%s' "$stripped" | grep -qE "$DATE_MODEL_RE" || continue
    echo "model-string: ✗ $f: ${hit}" >&2
    echo "    date-suffixed model ID — use the bare ID (e.g. claude-opus-4-8), never append a date." >&2
    fail=1
  done < <(grep -nE "$DATE_MODEL_RE" "$f" 2>/dev/null || true)
done

[ "$fail" = 0 ] && echo "model-string: ✓ no date-suffixed model IDs"
exit "$fail"
