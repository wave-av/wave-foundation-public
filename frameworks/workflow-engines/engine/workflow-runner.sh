#!/bin/bash
# Workflow Runner
# Executes agent workflows with checkpoint support, escalation, and outcome reporting
#
# Usage:
#   ./workflow-runner.sh <workflow-name> [--input key=value] [--resume checkpoint-id]
#
# Version: 1.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="$(dirname "$SCRIPT_DIR")"
STATE_DIR="${HOME}/.claude/state/workflows"
LOG_FILE="$STATE_DIR/runner.log"

# Source framework scripts
source "$SCRIPT_DIR/checkpoint-manager.sh" 2>/dev/null || true
source "$SCRIPT_DIR/escalation-handler.sh" 2>/dev/null || true
source "$SCRIPT_DIR/outcome-reporter.sh" 2>/dev/null || true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Initialize state directory
mkdir -p "$STATE_DIR"

# Logging
log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] [$level] $message" >>"$LOG_FILE"

  # DEBUG lines only surface when --verbose is set; everything else always prints.
  if [[ "$level" == "DEBUG" && "${VERBOSE:-false}" != "true" ]]; then
    return 0
  fi

  case "$level" in
    "INFO") echo -e "${BLUE}ℹ${NC} $message" ;;
    "DEBUG") echo -e "${BLUE}·${NC} $message" ;;
    "SUCCESS") echo -e "${GREEN}✓${NC} $message" ;;
    "WARNING") echo -e "${YELLOW}⚠${NC} $message" ;;
    "ERROR") echo -e "${RED}✗${NC} $message" ;;
  esac
}

# Parse arguments
parse_args() {
  WORKFLOW_NAME=""
  INPUTS=()
  RESUME_CHECKPOINT=""
  DRY_RUN=false
  VERBOSE=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input)
        INPUTS+=("$2")
        shift 2
        ;;
      --resume)
        RESUME_CHECKPOINT="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$WORKFLOW_NAME" ]]; then
          WORKFLOW_NAME="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$WORKFLOW_NAME" ]]; then
    echo "Error: Workflow name required"
    show_help
    exit 1
  fi
}

show_help() {
  cat <<EOF
Agent Workflow Runner

Usage:
    ./workflow-runner.sh <workflow-name> [options]

Options:
    --input key=value    Set workflow input
    --resume <id>        Resume from checkpoint
    --dry-run           Validate without executing
    --verbose           Enable verbose output
    --help              Show this help

Examples:
    ./workflow-runner.sh bug-fix --input issue_id=ABC-123
    ./workflow-runner.sh incident-response --resume chkpt_abc123
    ./workflow-runner.sh code-review --input pr_number=456 --verbose

Available Workflows:
EOF

  # List available workflows
  for workflow_dir in "$WORKFLOWS_DIR"/*/; do
    if [[ -f "${workflow_dir}workflow.json" ]]; then
      workflow_name=$(basename "$workflow_dir")
      description=$(jq -r '.description // "No description"' "${workflow_dir}workflow.json" 2>/dev/null || echo "No description")
      echo "    $workflow_name - $description"
    fi
  done
}

# Load workflow definition
load_workflow() {
  local name="$1"
  local workflow_file="$WORKFLOWS_DIR/$name/workflow.json"

  if [[ ! -f "$workflow_file" ]]; then
    log "ERROR" "Workflow not found: $name"
    exit 1
  fi

  # Validate against schema
  if command -v ajv &>/dev/null; then
    ajv validate -s "$SCRIPT_DIR/workflow-schema.json" -d "$workflow_file" 2>/dev/null || {
      log "WARNING" "Workflow validation failed, proceeding anyway"
    }
  fi

  cat "$workflow_file"
}

# Generate run ID
generate_run_id() {
  echo "run_$(date +%Y%m%d_%H%M%S)_$$"
}

# Execute a single step
execute_step() {
  local step_json="$1"
  local run_id="$2"
  local step_id
  local step_name
  local action_type

  step_id=$(echo "$step_json" | jq -r '.id')
  step_name=$(echo "$step_json" | jq -r '.name')
  action_type=$(echo "$step_json" | jq -r '.action.type')

  log "INFO" "Executing step: $step_name ($step_id)"

  # Check conditions
  local run_if
  run_if=$(echo "$step_json" | jq -r '.conditions.runIf // empty')
  if [[ -n "$run_if" ]]; then
    # TODO: Evaluate condition
    log "INFO" "Condition check: $run_if"
  fi

  # Create checkpoint if enabled
  local checkpoint_enabled
  checkpoint_enabled=$(echo "$step_json" | jq -r '.checkpoint.enabled // false')
  if [[ "$checkpoint_enabled" == "true" ]]; then
    create_checkpoint "$run_id" "$step_id" || true
  fi

  # Execute based on action type
  case "$action_type" in
    "agent-spawn")
      execute_agent_spawn "$step_json" "$run_id"
      ;;
    "tool-call")
      execute_tool_call "$step_json" "$run_id"
      ;;
    "validation")
      execute_validation "$step_json" "$run_id"
      ;;
    "checkpoint")
      create_checkpoint "$run_id" "$step_id"
      ;;
    "decision")
      execute_decision "$step_json" "$run_id"
      ;;
    "parallel")
      execute_parallel "$step_json" "$run_id"
      ;;
    "human-review")
      execute_human_review "$step_json" "$run_id"
      ;;
    "notification")
      execute_notification "$step_json" "$run_id"
      ;;
    *)
      log "ERROR" "Unknown action type: $action_type"
      return 1
      ;;
  esac
}

# Execute agent spawn action
execute_agent_spawn() {
  local step_json="$1"
  local run_id="$2"

  local agent_type
  local prompt
  local timeout

  agent_type=$(echo "$step_json" | jq -r '.action.agentType')
  prompt=$(echo "$step_json" | jq -r '.action.prompt')
  timeout=$(echo "$step_json" | jq -r '.action.timeout // 300')

  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would spawn agent: $agent_type"
    return 0
  fi

  log "INFO" "Spawning agent: $agent_type"

  # Use MCP agent spawner if available
  if [[ -x "$SCRIPT_DIR/../../scripts/mcp-agent-spawn.sh" ]]; then
    timeout "$timeout" bash "$SCRIPT_DIR/../../scripts/mcp-agent-spawn.sh" \
      --mode smart \
      --task "$prompt" \
      --run-id "$run_id"
  else
    log "WARNING" "Agent spawner not found, using direct Task tool"
    # Would call Task tool directly here
    echo "{\"agent_type\": \"$agent_type\", \"prompt\": \"$prompt\"}"
  fi
}

# Execute tool call action
execute_tool_call() {
  local step_json="$1"
  local run_id="$2"

  local tool
  local input

  tool=$(echo "$step_json" | jq -r '.action.tool')
  input=$(echo "$step_json" | jq -r '.action.input // {}')

  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would call tool: $tool"
    return 0
  fi

  log "INFO" "Calling tool: $tool"
  echo "{\"tool\": \"$tool\", \"input\": $input}"
}

# Execute validation action
execute_validation() {
  local step_json="$1"
  local run_id="$2"

  local validation_script
  validation_script=$(echo "$step_json" | jq -r '.action.script // empty')

  if [[ -n "$validation_script" && -x "$validation_script" ]]; then
    bash "$validation_script"
  else
    log "INFO" "No validation script specified"
  fi
}

# Execute decision action
execute_decision() {
  local step_json="$1"
  local run_id="$2"

  log "INFO" "Decision point reached - evaluating conditions"
  # Decision logic would be implemented here
}

# Execute parallel steps
execute_parallel() {
  local step_json="$1"
  local run_id="$2"

  local parallel_count
  parallel_count=$(echo "$step_json" | jq -r '.action.steps | length' 2>/dev/null || echo "0")

  log "INFO" "Executing $parallel_count parallel steps"
  # Would spawn parallel processes here
}

# Execute human review
execute_human_review() {
  local step_json="$1"
  local run_id="$2"

  log "INFO" "Human review required"
  # Would pause and wait for human input
}

# Execute notification
execute_notification() {
  local step_json="$1"
  local run_id="$2"

  local channel
  local message

  channel=$(echo "$step_json" | jq -r '.action.channel // "slack"')
  message=$(echo "$step_json" | jq -r '.action.message // "Workflow notification"')

  log "INFO" "Sending notification via $channel"

  if [[ "$DRY_RUN" != "true" ]]; then
    send_notification "$channel" "$message" || true
  fi
}

# Main workflow execution
run_workflow() {
  local workflow_json
  local run_id
  local start_time
  local end_time
  local duration

  workflow_json=$(load_workflow "$WORKFLOW_NAME")
  run_id=$(generate_run_id)
  start_time=$(date +%s)

  log "INFO" "Starting workflow: $WORKFLOW_NAME (Run ID: $run_id)"

  # Load required memories if specified
  local required_memories
  required_memories=$(echo "$workflow_json" | jq -r '.context.requiredMemories[]?' 2>/dev/null || echo "")
  if [[ -n "$required_memories" ]]; then
    log "INFO" "Loading required memories"
  fi

  # Resume from checkpoint if specified
  if [[ -n "$RESUME_CHECKPOINT" ]]; then
    log "INFO" "Resuming from checkpoint: $RESUME_CHECKPOINT"
    restore_checkpoint "$RESUME_CHECKPOINT" || {
      log "ERROR" "Failed to restore checkpoint"
      exit 1
    }
  fi

  # Execute steps
  local step_count
  local current_step=0
  step_count=$(echo "$workflow_json" | jq '.steps | length')

  echo "$workflow_json" | jq -c '.steps[]' | while read -r step; do
    ((current_step++))
    log "INFO" "Step $current_step/$step_count"

    execute_step "$step" "$run_id" || {
      local on_failure
      on_failure=$(echo "$step" | jq -r '.onFailure.action // "abort"')

      case "$on_failure" in
        "retry")
          log "WARNING" "Step failed, retrying..."
          execute_step "$step" "$run_id" || {
            log "ERROR" "Retry failed"
            handle_escalation "$WORKFLOW_NAME" "$run_id" "Step failed after retry"
            exit 1
          }
          ;;
        "skip")
          log "WARNING" "Step failed, skipping..."
          ;;
        "escalate")
          log "WARNING" "Step failed, escalating..."
          handle_escalation "$WORKFLOW_NAME" "$run_id" "Step failed"
          ;;
        "rollback")
          log "WARNING" "Step failed, rolling back..."
          rollback_to_last_checkpoint "$run_id"
          exit 1
          ;;
        "abort")
          log "ERROR" "Step failed, aborting workflow"
          report_outcome "$WORKFLOW_NAME" "$run_id" "failure" "Step execution failed"
          exit 1
          ;;
      esac
    }
  done

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  log "SUCCESS" "Workflow completed in ${duration}s"
  report_outcome "$WORKFLOW_NAME" "$run_id" "success" "Workflow completed successfully"
}

# Entry point
main() {
  parse_args "$@"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "Running in dry-run mode"
  fi

  run_workflow
}

main "$@"
