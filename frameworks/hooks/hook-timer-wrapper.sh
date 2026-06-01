#!/usr/bin/env bash
# hook-timer-wrapper.sh — measure a hook's wall-clock cost AND enforce a hard timeout.
#
# WHY: hooks run synchronously in the tool-call path; a slow or hung hook adds latency to
# every operation it guards. This wrapper (a) logs each run's duration to a JSONL cost file
# so you can attribute latency to specific hooks, and (b) kills the hook if it exceeds a
# timeout so a hang can never block the session indefinitely.
#
# Usage: hook-timer-wrapper.sh <hook-name> <command> [args...]
# Exit:  passes through the wrapped command's exit code; 124 on timeout (timeout(1) convention).
#
# Config (env):
#   CLAUDE_SESSION_ID   tags each log line with the session (default: "unknown")
#   HOOK_TIMER_TIMEOUT  seconds before the hook is killed (default: 10; "0" disables the kill)
#   HOOK_TIMER_FILE     JSONL cost log path (default: ${TMPDIR:-/tmp}/claude/hook-costs.jsonl)
#
# Provenance: hardened in wave-surfer-connect for hook cost attribution (E2).
set +e

HOOK_NAME="${1:?Usage: hook-timer-wrapper.sh <hook-name> <command> [args...]}"
shift

SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMEOUT_S="${HOOK_TIMER_TIMEOUT:-10}"
COST_FILE="${HOOK_TIMER_FILE:-${TMPDIR:-/tmp}/claude/hook-costs.jsonl}"

mkdir -p "$(dirname "${COST_FILE}")" 2>/dev/null

now_ms() { python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || echo "$(date +%s)000"; }

# Prefer GNU/BSD timeout(1); fall back to no-timeout if absent.
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

start_ms=$(now_ms)

exit_code=0
if [ -n "${TIMEOUT_BIN}" ] && [ "${TIMEOUT_S}" != "0" ]; then
  "${TIMEOUT_BIN}" "${TIMEOUT_S}" "$@" || exit_code=$?
else
  "$@" || exit_code=$?
fi

end_ms=$(now_ms)
duration_ms=$((end_ms - start_ms))

timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
printf '{"ts":"%s","hook":"%s","duration_ms":%s,"exit":%s,"session":"%s"}\n' \
  "${timestamp}" "${HOOK_NAME}" "${duration_ms}" "${exit_code}" "${SESSION_ID}" >>"${COST_FILE}" 2>/dev/null

if [ "${exit_code}" -eq 124 ]; then
  echo "HOOK TIMEOUT: '${HOOK_NAME}' exceeded ${TIMEOUT_S}s and was killed" >&2
fi

exit "${exit_code}"
