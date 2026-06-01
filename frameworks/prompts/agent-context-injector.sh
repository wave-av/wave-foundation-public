#!/bin/bash
# Hook: agent-context-injector.sh
# Event: PreToolUse (Task)
# Purpose: Inject AGENTS.md context into agent spawns
# Part of AGENTS.md Integration Plan (calm-roaming-pearl)

set -euo pipefail

# Get repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source the loader functions
source "$REPO_ROOT/.claude/hooks/agents-md-loader.sh"

# Read tool input (Task tool parameters)
TOOL_NAME="${TOOL_NAME:-}"
TOOL_INPUT="${TOOL_INPUT:-}"

# Only process Task tool calls
if [[ "$TOOL_NAME" != "Task" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Extract task description and prompt from tool input
# Tool input is JSON: { "description": "...", "prompt": "...", "subagent_type": "..." }
DESCRIPTION=$(echo "$TOOL_INPUT" | jq -r '.description // ""' 2>/dev/null || echo "")
PROMPT=$(echo "$TOOL_INPUT" | jq -r '.prompt // ""' 2>/dev/null || echo "")
SUBAGENT_TYPE=$(echo "$TOOL_INPUT" | jq -r '.subagent_type // ""' 2>/dev/null || echo "")

# Combine for domain detection
COMBINED_TEXT="$DESCRIPTION $PROMPT $SUBAGENT_TYPE"

# Detect domain
DOMAIN=$(detect_domain "$COMBINED_TEXT")

# Get agent-specific AGENTS.md if subagent_type is provided
get_agent_specific_md() {
  local AGENT_TYPE="$1"
  local AGENT_MD="$REPO_ROOT/.claude/agents/${AGENT_TYPE}.md"

  if [[ -f "$AGENT_MD" ]]; then
    # Check if agent has agents_md field in frontmatter
    local AGENTS_MD_REF
    AGENTS_MD_REF=$(head -50 "$AGENT_MD" | grep -E '^agents_md:' | sed 's/agents_md://' | tr -d ' ' || echo "")
    if [[ -n "$AGENTS_MD_REF" ]]; then
      echo "$REPO_ROOT/$AGENTS_MD_REF"
    fi
  fi
  echo ""
}

# Build context for agent spawn
build_agent_context() {
  local DOMAIN="$1"
  local AGENT_TYPE="$2"
  local CONTEXT=""

  # 1. Always include root AGENTS.md (first 2KB for routing)
  if [[ -f "$REPO_ROOT/AGENTS.md" ]]; then
    CONTEXT+="<!-- AGENTS.md Router -->\n"
    CONTEXT+=$(head -c 2048 "$REPO_ROOT/AGENTS.md")
    CONTEXT+="\n\n"
  fi

  # 2. Include domain-specific AGENTS.md
  if [[ -n "$DOMAIN" ]]; then
    local DOMAIN_MD
    DOMAIN_MD=$(get_domain_agents_md "$DOMAIN")
    if [[ -n "$DOMAIN_MD" && -f "$DOMAIN_MD" ]]; then
      CONTEXT+="<!-- Domain: $DOMAIN -->\n"
      CONTEXT+=$(head -c 4096 "$DOMAIN_MD")
      CONTEXT+="\n\n"
    fi

    # 3. Include MCP server AGENTS.md
    local MCP_MD
    MCP_MD=$(get_mcp_agents_md "$DOMAIN")
    if [[ -n "$MCP_MD" && -f "$MCP_MD" ]]; then
      CONTEXT+="<!-- MCP Server Context -->\n"
      CONTEXT+=$(head -c 2048 "$MCP_MD")
      CONTEXT+="\n\n"
    fi
  fi

  # 4. Include agent-specific AGENTS.md reference
  if [[ -n "$AGENT_TYPE" ]]; then
    local AGENT_MD
    AGENT_MD=$(get_agent_specific_md "$AGENT_TYPE")
    if [[ -n "$AGENT_MD" && -f "$AGENT_MD" ]]; then
      CONTEXT+="<!-- Agent-Specific Context -->\n"
      CONTEXT+=$(head -c 2048 "$AGENT_MD")
      CONTEXT+="\n\n"
    fi
  fi

  # 5. Include relevant .agents/ cross-cutting concerns
  local CROSS_CUTTING=""
  case "$DOMAIN" in
    security | auth)
      [[ -f "$REPO_ROOT/.agents/security.md" ]] && CROSS_CUTTING="$REPO_ROOT/.agents/security.md"
      ;;
    monitoring)
      [[ -f "$REPO_ROOT/.agents/observability.md" ]] && CROSS_CUTTING="$REPO_ROOT/.agents/observability.md"
      ;;
    testing)
      [[ -f "$REPO_ROOT/.agents/testing.md" ]] && CROSS_CUTTING="$REPO_ROOT/.agents/testing.md"
      ;;
  esac

  if [[ -n "$CROSS_CUTTING" && -f "$CROSS_CUTTING" ]]; then
    CONTEXT+="<!-- Cross-Cutting Concerns -->\n"
    CONTEXT+=$(head -c 2048 "$CROSS_CUTTING")
    CONTEXT+="\n"
  fi

  echo -e "$CONTEXT"
}

# Calculate context size
calculate_context_size() {
  local CONTEXT="$1"
  echo "${#CONTEXT}"
}

# Main execution
main() {
  # Build context for this agent spawn
  local CONTEXT
  CONTEXT=$(build_agent_context "$DOMAIN" "$SUBAGENT_TYPE")
  local CONTEXT_SIZE
  CONTEXT_SIZE=$(calculate_context_size "$CONTEXT")

  # Log context injection (for debugging)
  local LOG_DIR="$REPO_ROOT/.claude/state/agents"
  mkdir -p "$LOG_DIR"

  local LOG_ENTRY
  LOG_ENTRY=$(jq -n \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg domain "$DOMAIN" \
    --arg agent "$SUBAGENT_TYPE" \
    --arg size "$CONTEXT_SIZE" \
    '{timestamp: $timestamp, domain: $domain, agent: $agent, context_size: ($size | tonumber)}')

  echo "$LOG_ENTRY" >>"$LOG_DIR/context-injection.jsonl"

  # Output for hook system
  if [[ -n "$CONTEXT" ]]; then
    # Escape context for JSON
    local ESCAPED_CONTEXT
    ESCAPED_CONTEXT=$(echo "$CONTEXT" | jq -Rs .)

    cat <<EOF
{
  "modifyInput": {
    "prompt": {
      "prepend": $ESCAPED_CONTEXT
    }
  },
  "metadata": {
    "domain": "$DOMAIN",
    "agent": "$SUBAGENT_TYPE",
    "context_size": $CONTEXT_SIZE,
    "agents_md_loaded": true
  }
}
EOF
  else
    echo '{"continue": true}'
  fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
