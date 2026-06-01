#!/usr/bin/env bash
# hook-circuit-breaker-wrapper.sh — per-session self-healing circuit breaker for hooks.
#
# WHY: a single mis-behaving hook (a transient network call, a parse error on an unusual
# tool payload) can fail on every tool call and make the whole session unusable. This wrapper
# counts failures per (hook, session) and, after MAX_FAILURES, stops invoking the wrapped
# hook for the rest of the session — letting the operation proceed instead of dying.
#
# SECURITY: hooks named in PROTECTED_HOOKS (or matched via the PROTECTED_HOOKS_EXTRA env,
# a colon-separated substring list) are NEVER auto-disabled — a security guard must keep
# running even if it is flaky, otherwise the breaker becomes an attack vector ("make the
# guard fail 3× then do the dangerous thing"). Fail-closed for guards, fail-open for the rest.
#
# Usage: hook-circuit-breaker-wrapper.sh <hook-name> <command> [args...]
# Exit:  passes through the wrapped command's exit code; 0 when skipped by the breaker.
#
# Config (env):
#   CLAUDE_SESSION_ID       scopes the failure counters to one session (default: "unknown")
#   HOOK_BREAKER_MAX        failures before disabling a non-protected hook (default: 3)
#   HOOK_BREAKER_DIR        where counters live (default: ${TMPDIR:-/tmp}/claude/hook-failures)
#   PROTECTED_HOOKS_EXTRA   extra ":"-separated substrings to treat as security-critical
#
# Provenance: hardened in wave-surfer-connect after a flaky hook stalled a session (E9).
set +e

HOOK_NAME="${1:?Usage: hook-circuit-breaker-wrapper.sh <hook-name> <command> [args...]}"
shift

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
MAX_FAILURES="${HOOK_BREAKER_MAX:-3}"
FAILURE_DIR="${HOOK_BREAKER_DIR:-${TMPDIR:-/tmp}/claude/hook-failures}"
FAILURE_FILE="${FAILURE_DIR}/${HOOK_NAME}-${SESSION_ID}.count"

mkdir -p "${FAILURE_DIR}" 2>/dev/null

# Security-critical hooks — NEVER auto-disable. Matched as substrings of the hook name so a
# project can name its guards freely (e.g. "guard-secret-scan", "permission-rbac-enforcer").
PROTECTED_HOOKS=(
  "guard"
  "secret"
  "permission"
  "sql-guard"
  "circuit-breaker"
  "rls"
  "safety"
)

is_protected=false
for protected in "${PROTECTED_HOOKS[@]}"; do
  case "${HOOK_NAME}" in
    *"${protected}"*) is_protected=true; break ;;
  esac
done
if [ "${is_protected}" = "false" ] && [ -n "${PROTECTED_HOOKS_EXTRA:-}" ]; then
  IFS=':' read -ra extra <<<"${PROTECTED_HOOKS_EXTRA}"
  for protected in "${extra[@]}"; do
    [ -z "${protected}" ] && continue
    case "${HOOK_NAME}" in
      *"${protected}"*) is_protected=true; break ;;
    esac
  done
fi

# If the breaker is tripped for this non-protected hook, skip it and let the op proceed.
if [ "${is_protected}" = "false" ] && [ -f "${FAILURE_FILE}" ]; then
  failure_count=$(cat "${FAILURE_FILE}" 2>/dev/null || echo "0")
  if [ "${failure_count}" -ge "${MAX_FAILURES}" ] 2>/dev/null; then
    echo "CIRCUIT BREAKER: hook '${HOOK_NAME}' disabled after ${failure_count} failures this session" >&2
    exit 0
  fi
fi

# Run the wrapped hook, preserving its exit code.
exit_code=0
"$@" || exit_code=$?

# Count failures for non-protected hooks only.
if [ "${exit_code}" -ne 0 ] && [ "${is_protected}" = "false" ]; then
  current=$(cat "${FAILURE_FILE}" 2>/dev/null || echo "0")
  echo $((current + 1)) >"${FAILURE_FILE}" 2>/dev/null
fi

exit "${exit_code}"
