#!/usr/bin/env bash
# Lifecycle: Prompt Pre-Processor
# Event: UserPromptSubmit
# Action: Enrich automation commands with context, check audit gates
# Token cost: $0 (pure bash, never blocks)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hook-utils.sh"

# Read hook data from stdin
HOOK_DATA=$(read_stdin_json)
PROMPT=$(json_get "$HOOK_DATA" "prompt" 2>/dev/null || echo "")

if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# Check for /plan:ship without prior audit
case "$PROMPT" in
  */plan:ship*)
    # Check if audit was run recently
    AUDIT_FILE="$HOOK_STATE_DIR/audit-results.jsonl"
    if [[ ! -f "$AUDIT_FILE" ]]; then
      echo "Note: No /audit:execution results found. The ship skill will verify this." >&2
    fi
    ;;
esac

# Enrich /loop commands with state context
case "$PROMPT" in
  */loop*)
    ACTIVE_FILE="$HOOK_STATE_DIR/active-triggers.jsonl"
    if [[ -f "$ACTIVE_FILE" ]]; then
      ACTIVE_COUNT=$(wc -l <"$ACTIVE_FILE" 2>/dev/null | tr -d ' ')
      if [[ "$ACTIVE_COUNT" -gt 2 ]]; then
        echo "Note: $ACTIVE_COUNT active automation triggers. New loops may overlap." >&2
      fi
    fi
    ;;
esac

# Always exit 0 — never block user input
exit 0
