#!/bin/bash
# Escalation Handler
# Handles workflow escalations to appropriate channels (Slack, Linear, PagerDuty)
#
# Version: 1.0.0

# Configuration
ESCALATION_LOG="${HOME}/.claude/state/workflows/escalations.jsonl"
DEFAULT_SEVERITY="medium"

# Severity levels and their channels
declare -A SEVERITY_CHANNELS
SEVERITY_CHANNELS["low"]="slack"
SEVERITY_CHANNELS["medium"]="slack,linear"
SEVERITY_CHANNELS["high"]="slack,linear,pagerduty"
SEVERITY_CHANNELS["critical"]="slack,linear,pagerduty"

# Initialize
init_escalation() {
  mkdir -p "$(dirname "$ESCALATION_LOG")"
}

# Generate escalation ID
generate_escalation_id() {
  echo "esc_$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4 2>/dev/null || echo $$)"
}

# Handle escalation
# Args: workflow_name, run_id, reason, [severity]
handle_escalation() {
  local workflow_name="$1"
  local run_id="$2"
  local reason="$3"
  local severity="${4:-$DEFAULT_SEVERITY}"

  init_escalation

  local escalation_id
  escalation_id=$(generate_escalation_id)
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Log escalation
  local escalation_record
  escalation_record=$(
    cat <<EOF
{"escalation_id":"$escalation_id","workflow":"$workflow_name","run_id":"$run_id","reason":"$reason","severity":"$severity","timestamp":"$timestamp","status":"pending"}
EOF
  )
  echo "$escalation_record" >>"$ESCALATION_LOG"

  echo "Escalation created: $escalation_id (Severity: $severity)"

  # Get channels for severity
  local channels="${SEVERITY_CHANNELS[$severity]}"

  # Send to each channel
  IFS=',' read -ra CHANNEL_ARRAY <<<"$channels"
  for channel in "${CHANNEL_ARRAY[@]}"; do
    send_escalation "$channel" "$workflow_name" "$run_id" "$reason" "$severity" "$escalation_id"
  done

  echo "$escalation_id"
}

# Send escalation to channel
send_escalation() {
  local channel="$1"
  local workflow_name="$2"
  local run_id="$3"
  local reason="$4"
  local severity="$5"
  local escalation_id="$6"

  case "$channel" in
    "slack")
      send_slack_escalation "$workflow_name" "$run_id" "$reason" "$severity" "$escalation_id"
      ;;
    "linear")
      send_linear_escalation "$workflow_name" "$run_id" "$reason" "$severity" "$escalation_id"
      ;;
    "pagerduty")
      send_pagerduty_escalation "$workflow_name" "$run_id" "$reason" "$severity" "$escalation_id"
      ;;
    *)
      echo "Unknown escalation channel: $channel" >&2
      ;;
  esac
}

# Send Slack escalation
send_slack_escalation() {
  local workflow_name="$1"
  local run_id="$2"
  local reason="$3"
  local severity="$4"
  local escalation_id="$5"

  # Determine emoji and mention based on severity
  local emoji mention color
  case "$severity" in
    "low")
      emoji=":information_source:"
      mention=""
      color="#36a64f"
      ;;
    "medium")
      emoji=":warning:"
      mention=""
      color="#ffa500"
      ;;
    "high")
      emoji=":rotating_light:"
      mention="<!channel>"
      color="#ff6600"
      ;;
    "critical")
      emoji=":fire:"
      mention="<!here> <!channel>"
      color="#ff0000"
      ;;
  esac

  local slack_payload
  slack_payload=$(
    cat <<EOF
{
    "text": "$emoji ESCALATION: Workflow $workflow_name requires attention $mention",
    "attachments": [{
        "color": "$color",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "$emoji Workflow Escalation"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": "*Workflow:*\n$workflow_name"},
                    {"type": "mrkdwn", "text": "*Severity:*\n$severity"},
                    {"type": "mrkdwn", "text": "*Run ID:*\n$run_id"},
                    {"type": "mrkdwn", "text": "*Escalation ID:*\n$escalation_id"}
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "*Reason:*\n$reason"
                }
            },
            {
                "type": "actions",
                "elements": [
                    {
                        "type": "button",
                        "text": {"type": "plain_text", "text": "Acknowledge"},
                        "style": "primary",
                        "value": "$escalation_id"
                    },
                    {
                        "type": "button",
                        "text": {"type": "plain_text", "text": "View Details"},
                        "url": "${WORKFLOW_DASHBOARD_URL:-https://example.com}/workflows/$run_id"
                    }
                ]
            }
        ]
    }]
}
EOF
  )

  if [[ -n "${SLACK_ESCALATION_WEBHOOK:-}" ]]; then
    curl -s -X POST "$SLACK_ESCALATION_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "$slack_payload" >/dev/null 2>&1 || {
      echo "Warning: Failed to send Slack escalation" >&2
    }
    echo "Slack escalation sent"
  else
    echo "Slack escalation skipped (SLACK_ESCALATION_WEBHOOK not set)"
  fi
}

# Send Linear escalation
send_linear_escalation() {
  local workflow_name="$1"
  local run_id="$2"
  local reason="$3"
  local severity="$4"
  local escalation_id="$5"

  # Map severity to Linear priority
  local priority
  case "$severity" in
    "low") priority="4" ;;      # Low
    "medium") priority="3" ;;   # Medium
    "high") priority="2" ;;     # High
    "critical") priority="1" ;; # Urgent
  esac

  # Create Linear issue via MCP if available
  if command -v mcp__linear__create_issue &>/dev/null; then
    echo "Would create Linear issue with priority $priority"
    # mcp__linear__create_issue(
    #   title="[ESCALATION] Workflow $workflow_name failed",
    #   description="...",
    #   priority=$priority,
    #   labels=["escalation", "workflow", "$severity"]
    # )
  else
    echo "Linear escalation skipped (MCP not available)"
  fi
}

# Send PagerDuty escalation
send_pagerduty_escalation() {
  local workflow_name="$1"
  local run_id="$2"
  local reason="$3"
  local severity="$4"
  local escalation_id="$5"

  # Map severity to PagerDuty severity
  local pd_severity
  case "$severity" in
    "low") pd_severity="info" ;;
    "medium") pd_severity="warning" ;;
    "high") pd_severity="error" ;;
    "critical") pd_severity="critical" ;;
  esac

  local pd_payload
  pd_payload=$(
    cat <<EOF
{
    "routing_key": "${PAGERDUTY_ROUTING_KEY:-}",
    "event_action": "trigger",
    "dedup_key": "$escalation_id",
    "payload": {
        "summary": "Workflow escalation: $workflow_name - $reason",
        "severity": "$pd_severity",
        "source": "workflow-runner",
        "custom_details": {
            "workflow": "$workflow_name",
            "run_id": "$run_id",
            "escalation_id": "$escalation_id",
            "reason": "$reason"
        }
    }
}
EOF
  )

  if [[ -n "${PAGERDUTY_ROUTING_KEY:-}" ]]; then
    curl -s -X POST "https://events.pagerduty.com/v2/enqueue" \
      -H "Content-Type: application/json" \
      -d "$pd_payload" >/dev/null 2>&1 || {
      echo "Warning: Failed to send PagerDuty escalation" >&2
    }
    echo "PagerDuty escalation sent"
  else
    echo "PagerDuty escalation skipped (PAGERDUTY_ROUTING_KEY not set)"
  fi
}

# Acknowledge escalation
acknowledge_escalation() {
  local escalation_id="$1"
  local acknowledged_by="${2:-${USER:-unknown}}"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Log acknowledgment
  echo "{\"escalation_id\":\"$escalation_id\",\"action\":\"acknowledged\",\"by\":\"$acknowledged_by\",\"timestamp\":\"$timestamp\"}" >>"$ESCALATION_LOG"

  echo "Escalation $escalation_id acknowledged by $acknowledged_by"
}

# Resolve escalation
resolve_escalation() {
  local escalation_id="$1"
  local resolved_by="${2:-${USER:-unknown}}"
  local resolution="${3:-Resolved}"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Log resolution
  echo "{\"escalation_id\":\"$escalation_id\",\"action\":\"resolved\",\"by\":\"$resolved_by\",\"resolution\":\"$resolution\",\"timestamp\":\"$timestamp\"}" >>"$ESCALATION_LOG"

  echo "Escalation $escalation_id resolved"
}

# List pending escalations
list_pending_escalations() {
  init_escalation

  echo "Pending Escalations"
  echo "==================="

  if [[ ! -f "$ESCALATION_LOG" ]]; then
    echo "No escalations found"
    return
  fi

  # Find escalations not yet resolved
  local pending
  pending=$(grep '"status":"pending"' "$ESCALATION_LOG" 2>/dev/null | tail -20)

  if [[ -z "$pending" ]]; then
    echo "No pending escalations"
    return
  fi

  echo "$pending" | while read -r line; do
    local esc_id
    local workflow
    local severity
    local timestamp

    esc_id=$(echo "$line" | jq -r '.escalation_id')
    workflow=$(echo "$line" | jq -r '.workflow')
    severity=$(echo "$line" | jq -r '.severity')
    timestamp=$(echo "$line" | jq -r '.timestamp')

    local severity_icon
    case "$severity" in
      "low") severity_icon="○" ;;
      "medium") severity_icon="△" ;;
      "high") severity_icon="◆" ;;
      "critical") severity_icon="●" ;;
    esac

    echo "  $severity_icon [$severity] $workflow - $esc_id @ $timestamp"
  done
}

# If run directly, provide CLI
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    escalate)
      handle_escalation "${2:-}" "${3:-}" "${4:-}" "${5:-medium}"
      ;;
    ack | acknowledge)
      acknowledge_escalation "${2:-}" "${3:-}"
      ;;
    resolve)
      resolve_escalation "${2:-}" "${3:-}" "${4:-Resolved}"
      ;;
    list)
      list_pending_escalations
      ;;
    *)
      echo "Escalation Handler"
      echo ""
      echo "Usage: $0 <command> [args]"
      echo ""
      echo "Commands:"
      echo "  escalate <workflow> <run_id> <reason> [severity]"
      echo "  ack <escalation_id> [user]"
      echo "  resolve <escalation_id> [user] [resolution]"
      echo "  list                         List pending escalations"
      echo ""
      echo "Severity levels: low, medium, high, critical"
      ;;
  esac
fi
