#!/bin/bash
# Hook: Circuit breaker — blocks dangerous commands
# Event: PreToolUse (matcher: Bash)
# Only checks the PRIMARY command, not search patterns in grep/xargs arguments
set +e
input=$(cat)
cmd=$(echo "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# Extract the primary command (first word, skip env vars)
primary=$(echo "$cmd" | sed 's/^[A-Z_]*=[^ ]* //' | awk '{print $1}')

# Only block if the PRIMARY command is dangerous (not search patterns)
case "$primary" in
  rm)
    echo "$cmd" | grep -qE '^rm\s+-rf\s+(/|~|/home)' && {
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: Recursive delete of root/home"}}'
      exit 0
    }
    ;;
  chmod)
    echo "$cmd" | grep -qE 'chmod\s+777' && {
      echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: chmod 777"}}'
      exit 0
    }
    ;;
  mkfs*)
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: mkfs"}}'
    exit 0
    ;;
esac

# Block piped execution (curl|sh, wget|bash) — but not grep patterns containing the string
echo "$cmd" | grep -qE '(curl|wget)\s.*\|\s*(sh|bash)$' && {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: Piped remote execution"}}'
  exit 0
}

# Block force push to main/master — only actual git push commands
echo "$cmd" | grep -qE '^git\s+push\s+--force.*(main|master)' && {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: Force push to main/master"}}'
  exit 0
}

# Block SQL destruction — only if it's an actual SQL command (not in a grep pattern)
if [ "$primary" = "psql" ] || [ "$primary" = "mysql" ] || [ "$primary" = "sqlite3" ]; then
  echo "$cmd" | grep -qiE 'DROP\s+(TABLE|DATABASE)|TRUNCATE.*CASCADE' && {
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: Destructive SQL"}}'
    exit 0
  }
fi

exit 0
