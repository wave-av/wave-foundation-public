#!/usr/bin/env bash
# lint-cache-control.sh — nudge every Claude-API call site that has a cacheable prefix to actually cache it.
#
# Prompt caching is a prefix match: a stable `system` prefix served uncached costs full input price
# ($5/MTok on Opus 4.8) on EVERY request; cached it costs ~0.1x. A real audit of the wave.online
# workspace found 77 of 80 SDK call sites missing cache_control → the Console reported ZERO cache use.
# As WSC is decomposed into per-product spoke repos, this gate (inherited via foundation-gate.yml@v1)
# keeps the new repos from re-introducing that class — every spoke that builds an Anthropic request with
# a `system` prefix gets nudged to set cache_control on it.
#
# ADVISORY by design (continue-on-error during rollout): a finding means "this prefix is probably
# cacheable and isn't" — but a single-shot call whose prefix genuinely varies per request SHOULD NOT
# cache (it would only pay the write premium). Mark those `cache-exempt` (or 'claude-api-lint: ignore')
# rather than adding a useless breakpoint.
#
# What it flags (per file, heuristic): a file that (a) builds an Anthropic Messages request
# (messages.create / beta.messages / /v1/messages), (b) sets a `system` field, and (c) has NO
# cache_control / cacheControl anywhere — and isn't escaped.
#
# Escape:  line/file containing `cache-exempt` or `claude-api-lint: ignore`/`skip` (prefix varies → don't cache).
# Usage:   lint-cache-control.sh [file ...]   (pre-commit passes changed files; no args → git-tracked code)
# Exit:    0 clean, 1 findings (printed file:line + the fix). Wire continue-on-error during rollout.
set -euo pipefail

CODE_RE='\.(py|ts|tsx|js|jsx|mjs|cjs|go|rb|java|kt|cs|php)$'   # not .sh — request-builders aren't shell
CLAUDE_RE='anthropic|claude-(opus|sonnet|haiku)|Anthropic\('
REQUEST_RE='messages\.create|\.messages\.stream|beta\.messages|/v1/messages|messages\.batches'
# a `system` REQUEST field: py kwarg `system=`, json `"system":`, ts/js object `system:`.
SYSTEM_RE='(^|[^A-Za-z_."'"'"'])system[[:space:]]*[:=]'
CACHE_RE='cache_control|cacheControl'

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
elif git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
fi

findings=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  printf '%s\n' "$f" | grep -qE "$CODE_RE" || continue
  # Same exclusions as the shape linter, plus test/bench/example/migrator trees — caching is irrelevant
  # in throwaway one-shot scripts, and a migrator that EMITS cache_control as a string would self-trip.
  case "$f" in
    staging/* | */node_modules/* | node_modules/* | */dist/* | dist/* | .foundation/* | */vendor/* | vendor/* \
    | */tests/* | *_test.* | *.test.* | *.spec.* | *bench* | *example* | */migrators/* | */__tests__/*) continue ;;
  esac
  grep -q 'claude-api-lint: skip' "$f" 2>/dev/null && continue
  grep -q 'cache-exempt' "$f" 2>/dev/null && continue

  # must build an Anthropic request AND look Claude-related
  grep -qE "$REQUEST_RE" "$f" 2>/dev/null || continue
  grep -qE "$CLAUDE_RE" "$f" 2>/dev/null || continue
  # already caches somewhere → good, skip
  grep -qE "$CACHE_RE" "$f" 2>/dev/null && continue

  # find the first `system` field assignment not carrying an inline ignore; report it.
  while IFS= read -r hit; do
    lineno="${hit%%:*}"
    text="${hit#*:}"
    case "$text" in *claude-api-lint:\ ignore* | *cache-exempt*) continue ;; esac
    echo "cache-control-lint: ⚠ $f:$lineno" >&2
    echo "    Anthropic request sets a 'system' prefix but no cache_control found in this file." >&2
    echo "    Cache the stable prefix: system=[{type:'text',text:...,cache_control:{type:'ephemeral'}}]" >&2
    echo "    (Opus 4.8 min cacheable prefix = 4096 tokens. If the prefix varies per request, mark it 'cache-exempt'.)" >&2
    findings=$((findings + 1))
    break   # one nudge per file is enough
  done < <(grep -nE "$SYSTEM_RE" "$f" 2>/dev/null || true)
done

if [ "$findings" -gt 0 ]; then
  echo "cache-control-lint: $findings file(s) build a Claude request with an uncached system prefix. See frameworks/claude-api/prompt-caching.md. Escape a genuinely-varying prefix with 'cache-exempt'." >&2
  exit 1
fi
echo "cache-control-lint: ✓ every Claude request with a system prefix caches it (or is exempt)"
exit 0
