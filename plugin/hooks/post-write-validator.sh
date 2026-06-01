#!/usr/bin/env bash
# Post-write validator: checks written files for common issues
#
# This hook runs after file writes to catch violations early.
# It validates against WAVE core rules including:
#   - Zero mock data policy
#   - Semantic color token requirement (OKLCH)
#   - No hardcoded hex colors
#   - No @ts-ignore directives
#
# Usage: Called automatically by Claude Code post-write hook
#   ./post-write-validator.sh <file-path>
#
# Exit codes:
#   0 - File passes all checks (or file type not applicable)
#   1 - Critical violation found (mock data)
#
# Related:
#   .claude/rules/00-core/no-mock-data.md
#   .claude/rules/02-frontend/oklch-colors.md

set -euo pipefail

FILE_PATH="${1:-}"

# Skip if no file path provided
if [ -z "${FILE_PATH}" ]; then
  exit 0
fi

# Skip non-source files
case "${FILE_PATH}" in
  *.ts | *.tsx | *.js | *.jsx) ;; # Process these
  *)
    exit 0 # Skip non-JS/TS files
    ;;
esac

# Skip node_modules, dist, and test fixtures
case "${FILE_PATH}" in
  */node_modules/* | */dist/* | */.next/* | */__fixtures__/* | */__mocks__/*)
    exit 0
    ;;
esac

HAD_WARNING=0

# Check for mock data patterns (CRITICAL - blocks write)
if grep -qE '(const\s+(mock|fake|dummy)[A-Z]\w*\s*=|mockUser|mockData|fakeMetrics|generateMockData|isAuthenticated\s*=\s*true)' "${FILE_PATH}" 2>/dev/null; then
  echo "ERROR: Mock data detected in ${FILE_PATH}" >&2
  echo "  WAVE requires real service integrations. See .claude/rules/00-core/no-mock-data.md" >&2
  exit 1
fi

# Check for hardcoded Tailwind color classes (WARNING)
if grep -qE '\b(bg|text|border|ring|outline|shadow|accent|fill|stroke|from|via|to)-(red|blue|green|yellow|purple|pink|indigo|orange|teal|cyan|lime|emerald|violet|fuchsia|rose|amber|sky|slate|gray|zinc|neutral|stone)-[0-9]{2,3}\b' "${FILE_PATH}" 2>/dev/null; then
  echo "WARNING: Hardcoded Tailwind color class detected in ${FILE_PATH}" >&2
  echo "  Use semantic tokens (e.g., bg-primary-600) instead. See .claude/rules/02-frontend/oklch-colors.md" >&2
  HAD_WARNING=1
fi

# Check for hardcoded hex colors (WARNING)
if grep -qE "(color|background|border|fill|stroke)\s*[:=]\s*['\"]#[0-9a-fA-F]{3,8}['\"]" "${FILE_PATH}" 2>/dev/null; then
  echo "WARNING: Hardcoded hex color detected in ${FILE_PATH}" >&2
  echo "  Use OKLCH semantic tokens instead. See .claude/rules/02-frontend/oklch-colors.md" >&2
  HAD_WARNING=1
fi

# Check for @ts-ignore (BLOCKING - must fix the type error)
if grep -qE '@ts-ignore|@ts-nocheck' "${FILE_PATH}" 2>/dev/null; then
  echo "ERROR: @ts-ignore/@ts-nocheck detected in ${FILE_PATH}" >&2
  echo "  Fix the type error instead of suppressing it." >&2
  exit 1
fi

# Check for console.log in service files (BLOCKING - use BaseService logger)
if [[ "${FILE_PATH}" == *"/services/"* ]] && grep -qE 'console\.(log|warn|error|info|debug)\(' "${FILE_PATH}" 2>/dev/null; then
  echo "ERROR: console.log detected in service file ${FILE_PATH}" >&2
  echo "  Use this.logger from BaseService instead." >&2
  exit 1
fi

# Check for throw in service files (BLOCKING - must return ServiceResult)
if [[ "${FILE_PATH}" == *"/services/"* ]] && grep -qE 'throw new (Error|TypeError|RangeError)\(' "${FILE_PATH}" 2>/dev/null; then
  echo "ERROR: throw detected in service file ${FILE_PATH}" >&2
  echo "  Return ServiceResult<T> with { success: false, error } instead." >&2
  exit 1
fi

# Check for untraced fetch/axios in service files (BLOCKING — observability requirement)
if [[ "${FILE_PATH}" == *"/services/"* ]] && grep -qE 'await\s+(fetch|axios)\(' "${FILE_PATH}" 2>/dev/null; then
  if ! grep -qE 'traceExternalAPI' "${FILE_PATH}" 2>/dev/null; then
    echo "ERROR: Untraced external API call in ${FILE_PATH}" >&2
    echo "  Wrap with traceExternalAPI('service', 'op', fn)." >&2
    exit 1
  fi
fi

# Check for unchecked Supabase responses (WARNING)
if grep -qE 'supabase\.from\(' "${FILE_PATH}" 2>/dev/null; then
  if grep -qE 'const\s*\{\s*data\s*\}' "${FILE_PATH}" 2>/dev/null && ! grep -qE 'const\s*\{\s*data\s*,\s*error' "${FILE_PATH}" 2>/dev/null; then
    echo "WARNING: Supabase response missing error check in ${FILE_PATH}" >&2
    echo "  Destructure both { data, error } and handle error case." >&2
    HAD_WARNING=1
  fi
fi

# Golden-path: BaseService + constructor injection checks
# MOVED to prompt hook (PostToolUse type:prompt on **/services/**) for semantic accuracy.
# The prompt hook catches cases regex misses (e.g., ServiceResult return validation).
# Regex checks for throw/console.log/untraced-fetch kept above as fast first-pass.

# CWE-89: SQL injection via string interpolation in Supabase rpc calls
if grep -qE 'supabase\.rpc\([^)]*\$\{' "${FILE_PATH}" 2>/dev/null; then
  echo "WARNING: Possible SQL injection in Supabase rpc call (CWE-89) in ${FILE_PATH}" >&2
  echo "  Use parameterized queries instead of template literals. See .claude/rules/56-reviewbot/review-resolution-patterns.md" >&2
  HAD_WARNING=1
fi

# CWE-79: XSS via dangerouslySetInnerHTML without sanitization
if grep -qE 'dangerouslySetInnerHTML' "${FILE_PATH}" 2>/dev/null; then
  if ! grep -qE 'DOMPurify|sanitize|escape' "${FILE_PATH}" 2>/dev/null; then
    echo "WARNING: dangerouslySetInnerHTML without sanitization (CWE-79) in ${FILE_PATH}" >&2
    echo "  Add DOMPurify.sanitize() or equivalent. See .claude/rules/56-reviewbot/review-resolution-patterns.md" >&2
    HAD_WARNING=1
  fi
fi

# CWE-287: API routes missing auth guard
if [[ "${FILE_PATH}" == */api/* ]] && [[ "${FILE_PATH}" != */api/public/* ]] && [[ "${FILE_PATH}" != */api/health* ]] && [[ "${FILE_PATH}" != */api/webhooks/* ]]; then
  if grep -qE 'export\s+async\s+function\s+(GET|POST|PUT|DELETE|PATCH)' "${FILE_PATH}" 2>/dev/null; then
    if ! grep -qE 'supabase\.auth\.getUser|getServerSession|auth\(\)|verifyApiKey' "${FILE_PATH}" 2>/dev/null; then
      echo "WARNING: API route without auth guard (CWE-287) in ${FILE_PATH}" >&2
      echo "  Add supabase.auth.getUser() or equivalent auth check. See .claude/rules/00-core/golden-path-enforcement.md" >&2
      HAD_WARNING=1
    fi
  fi
fi

# CWE-918: User-controlled URLs in fetch calls
if grep -qE 'fetch\(\s*(params|query|body|request|searchParams|url)\b' "${FILE_PATH}" 2>/dev/null; then
  echo "WARNING: fetch() with possibly user-controlled URL (CWE-918) in ${FILE_PATH}" >&2
  echo "  Validate URL against an allowlist before fetching. See .claude/rules/56-reviewbot/review-resolution-patterns.md" >&2
  HAD_WARNING=1
fi

if [ ${HAD_WARNING} -eq 1 ]; then
  echo "Post-write validation completed with warnings for ${FILE_PATH}" >&2
fi

exit 0
