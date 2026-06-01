#!/usr/bin/env bash
# Version: 1.2.0
# Created: 2026-01-16
# Updated: 2026-01-31 - Added updatedInput functions for PreToolUse modification hooks
#
# Library for PreToolUse additionalContext pattern (Claude Code 2.1.9)
# Provides functions for injecting context that Claude sees before tool execution
#
# Usage:
#   source "$(dirname "$0")/lib/additional-context-lib.sh"
#   HOOK_INPUT=$(cat)
#   inject_additional_context "$HOOK_INPUT" "Your context string" "allow"
#
# Hook Output Format (JSON on stdout, exit 0):
# {
#   "continue": true,
#   "hookSpecificOutput": {
#     "hookEventName": "PreToolUse",
#     "permissionDecision": "allow|deny|ask",
#     "permissionDecisionReason": "explanation",
#     "updatedInput": { "field": "modified_value" },
#     "additionalContext": "Context string Claude will see"
#   }
# }
#
# Decision Options:
# - allow: Auto-approve without permission prompt
# - deny: Block tool call, show reason to Claude
# - ask: Request user confirmation (with optional modified input)

set +e # Graceful error handling
trap 'true' ERR

# Check for jq dependency
if ! command -v jq &>/dev/null; then
  echo '{"error": "jq is required for additional-context-lib.sh"}' >&2
  exit 1
fi

# Inject additionalContext into hook output
# Arguments:
#   $1 - Original hook input JSON
#   $2 - Context string to inject (Claude will see this)
#   $3 - (Optional) Permission decision: allow, deny, or ask
#   $4 - (Optional) Permission decision reason
#
# Example:
#   inject_additional_context "$HOOK_INPUT" "TIP: Use foo instead of bar" "allow"
inject_additional_context() {
  local input="$1"
  local context="$2"
  local decision="${3:-}"
  local reason="${4:-}"

  # Validate input
  if [[ -z "$input" ]]; then
    echo '{"error": "Empty input provided to inject_additional_context"}'
    return 1
  fi

  if [[ -z "$context" ]]; then
    # No context to inject, return original input
    echo "$input"
    return 0
  fi

  local output
  if [[ -n "$decision" && -n "$reason" ]]; then
    output=$(echo "$input" | jq \
      --arg ctx "$context" \
      --arg dec "$decision" \
      --arg rsn "$reason" \
      '. + {
                continue: true,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    additionalContext: $ctx,
                    permissionDecision: $dec,
                    permissionDecisionReason: $rsn
                }
            }')
  elif [[ -n "$decision" ]]; then
    output=$(echo "$input" | jq \
      --arg ctx "$context" \
      --arg dec "$decision" \
      '. + {
                continue: true,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    additionalContext: $ctx,
                    permissionDecision: $dec
                }
            }')
  else
    output=$(echo "$input" | jq \
      --arg ctx "$context" \
      '. + {
                continue: true,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    additionalContext: $ctx
                }
            }')
  fi

  echo "$output"
}

# Deny a tool call with a reason
deny_tool_call() {
  local input="$1"
  local reason="$2"
  local context="${3:-}"

  if [[ -z "$input" ]]; then
    echo '{"error": "Empty input provided to deny_tool_call"}'
    return 1
  fi

  local output
  if [[ -n "$context" ]]; then
    output=$(echo "$input" | jq \
      --arg rsn "$reason" \
      --arg ctx "$context" \
      '. + {
                continue: false,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: "deny",
                    permissionDecisionReason: $rsn,
                    additionalContext: $ctx
                }
            }')
  else
    output=$(echo "$input" | jq \
      --arg rsn "$reason" \
      '. + {
                continue: false,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: "deny",
                    permissionDecisionReason: $rsn
                }
            }')
  fi

  echo "$output"
}

# Modify tool input before execution (LEGACY - use return_updated_input instead)
modify_tool_input() {
  local input="$1"
  local field="$2"
  local value="$3"

  if [[ -z "$input" || -z "$field" ]]; then
    echo '{"error": "Missing required arguments for modify_tool_input"}'
    return 1
  fi

  echo "$input" | jq \
    --arg f "$field" \
    --arg v "$value" \
    '.hookSpecificOutput.updatedInput[$f] = $v'
}

# ═══════════════════════════════════════════════════════════════
# updatedInput Functions (Claude Code 2.1.0+)
# ═══════════════════════════════════════════════════════════════
# These functions enable PreToolUse hooks to modify tool inputs
# before execution. Use when hooks need to transform, sanitize,
# or fix inputs rather than just approve/deny.
#
# IMPORTANT: When a hook outputs updatedInput, Claude uses the
# modified input for the tool call instead of the original.
#
# Configuration: Set "updatedInput": true in settings.json hook config
# Example:
# {
#   "PreToolUse": [{
#     "matcher": "mcp__supabase__execute_sql",
#     "hooks": [{
#       "type": "command",
#       "command": ".claude/hooks/sql-sanitizer.sh",
#       "timeout": 3,
#       "updatedInput": true
#     }]
#   }]
# }

# Return modified input with updatedInput field
# This is the PRIMARY function for input modification hooks
return_updated_input() {
  local input="$1"
  local updated_input="$2"
  local decision="${3:-allow}"
  local context="${4:-}"

  if [[ -z "$input" || -z "$updated_input" ]]; then
    echo '{"error": "Missing required arguments for return_updated_input"}'
    return 1
  fi

  local output
  if [[ -n "$context" ]]; then
    output=$(echo "$input" | jq \
      --argjson upd "$updated_input" \
      --arg dec "$decision" \
      --arg ctx "$context" \
      '. + {
                continue: true,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: $dec,
                    updatedInput: $upd,
                    additionalContext: $ctx
                }
            }')
  else
    output=$(echo "$input" | jq \
      --argjson upd "$updated_input" \
      --arg dec "$decision" \
      '. + {
                continue: true,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: $dec,
                    updatedInput: $upd
                }
            }')
  fi

  echo "$output"
}

# Modify a single field in tool_input and return updatedInput
modify_and_return() {
  local input="$1"
  local field="$2"
  local value="$3"
  local decision="${4:-allow}"
  local context="${5:-}"

  if [[ -z "$input" || -z "$field" ]]; then
    echo '{"error": "Missing required arguments for modify_and_return"}'
    return 1
  fi

  local current_input
  current_input=$(echo "$input" | jq '.tool_input // {}')

  local modified
  modified=$(echo "$current_input" | jq --arg f "$field" --arg v "$value" '.[$f] = $v')

  return_updated_input "$input" "$modified" "$decision" "$context"
}

# Modify multiple fields in tool_input and return updatedInput
modify_multiple_and_return() {
  local input="$1"
  local updates="$2"
  local decision="${3:-allow}"
  local context="${4:-}"

  if [[ -z "$input" || -z "$updates" ]]; then
    echo '{"error": "Missing required arguments for modify_multiple_and_return"}'
    return 1
  fi

  local current_input
  current_input=$(echo "$input" | jq '.tool_input // {}')

  local modified
  modified=$(echo "$current_input" | jq --argjson upd "$updates" '. + $upd')

  return_updated_input "$input" "$modified" "$decision" "$context"
}

# Request user confirmation before proceeding
ask_for_confirmation() {
  local input="$1"
  local context="$2"
  local updated_input="${3:-}"

  if [[ -z "$input" ]]; then
    echo '{"error": "Empty input provided to ask_for_confirmation"}'
    return 1
  fi

  local output
  if [[ -n "$updated_input" ]]; then
    output=$(echo "$input" | jq \
      --arg ctx "$context" \
      --argjson upd "$updated_input" \
      '. + {
                continue: true,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: "ask",
                    additionalContext: $ctx,
                    updatedInput: $upd
                }
            }')
  else
    output=$(echo "$input" | jq \
      --arg ctx "$context" \
      '. + {
                continue: true,
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: "ask",
                    additionalContext: $ctx
                }
            }')
  fi

  echo "$output"
}

# Helper functions
get_tool_name() {
  local input="$1"
  echo "$input" | jq -r '.tool // .tool_name // ""' 2>/dev/null || echo ""
}

get_tool_input() {
  local input="$1"
  echo "$input" | jq -r '.tool_input // {}' 2>/dev/null || echo "{}"
}

should_process() {
  local input="$1"
  local pattern="$2"
  local tool_name
  tool_name=$(get_tool_name "$input")
  local regex="${pattern//\*/.*}"
  if [[ "$tool_name" =~ ^${regex}$ ]]; then
    return 0
  else
    return 1
  fi
}

combine_context() {
  local IFS=$'\n'
  echo "$*"
}

# Performance tracking
perf_start() {
  HOOK_START_TIME=$(date +%s%N)
  HOOK_START_MS=$((HOOK_START_TIME / 1000000))
}

perf_end() {
  local hook_name="$1"
  local decision="$2"
  local tool_name="${3:-unknown}"

  if [[ -z "$HOOK_START_TIME" ]]; then
    return 0
  fi

  local end_time
  end_time=$(date +%s%N)
  local end_ms
  end_ms=$((end_time / 1000000))
  local duration_ms
  duration_ms=$((end_ms - HOOK_START_MS))

  local metrics_dir="${CLAUDE_PROJECT_DIR:-.}/.claude/logs/metrics"
  mkdir -p "$metrics_dir" 2>/dev/null || true

  local metrics_file="$metrics_dir/hook-performance.jsonl"

  cat >>"$metrics_file" 2>/dev/null <<EOF || true
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","hook":"$hook_name","tool":"$tool_name","decision":"$decision","duration_ms":$duration_ms,"session":"${CLAUDE_SESSION_ID:-unknown}"}
EOF

  if [[ "$duration_ms" -gt 500 ]]; then
    echo "[PERF WARNING] $hook_name took ${duration_ms}ms" >&2
  fi
}

get_perf_summary() {
  local count="${1:-50}"
  local metrics_file="${CLAUDE_PROJECT_DIR:-.}/.claude/logs/metrics/hook-performance.jsonl"

  if [[ ! -f "$metrics_file" ]]; then
    echo "No performance data available"
    return 0
  fi

  echo "Hook Performance Summary (last $count entries):"
  echo "─────────────────────────────────────────"

  tail -n "$count" "$metrics_file" 2>/dev/null | jq -s '
        group_by(.hook) |
        map({
            hook: .[0].hook,
            count: length,
            avg_ms: (map(.duration_ms) | add / length | floor),
            max_ms: (map(.duration_ms) | max)
        }) |
        sort_by(.avg_ms) |
        reverse[]
    ' 2>/dev/null || echo "Unable to parse metrics"
}

# Export functions for use in sourcing scripts
export -f inject_additional_context
export -f deny_tool_call
export -f modify_tool_input
export -f return_updated_input
export -f modify_and_return
export -f modify_multiple_and_return
export -f ask_for_confirmation
export -f get_tool_name
export -f get_tool_input
export -f should_process
export -f combine_context
export -f perf_start
export -f perf_end
export -f get_perf_summary

exit 0
