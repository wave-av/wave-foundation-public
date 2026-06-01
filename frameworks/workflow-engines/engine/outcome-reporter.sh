#!/bin/bash
# Outcome Reporter
# Reports workflow outcomes to various destinations (Linear, Slack, Supabase, etc.)
#
# Version: 1.0.0

# Configuration
REPORTS_DIR="${HOME}/.claude/state/workflows/reports"
DEFAULT_DESTINATIONS="file"

# Initialize reports directory
init_reports() {
  mkdir -p "$REPORTS_DIR"
}

# Generate report ID
generate_report_id() {
  echo "rpt_$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4 2>/dev/null || echo $$)"
}

# Create outcome report
# Args: workflow_name, run_id, status, message, [metrics_json]
report_outcome() {
  local workflow_name="$1"
  local run_id="$2"
  local status="$3"
  local message="$4"
  local metrics="${5:-{}}"

  init_reports

  local report_id
  report_id=$(generate_report_id)
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build report
  local report
  report=$(
    cat <<EOF
{
    "report_id": "$report_id",
    "workflow": "$workflow_name",
    "run_id": "$run_id",
    "status": "$status",
    "message": "$message",
    "timestamp": "$timestamp",
    "metrics": $metrics,
    "environment": {
        "hostname": "$(hostname)",
        "user": "${USER:-unknown}",
        "working_dir": "$(pwd)"
    }
}
EOF
  )

  # Save to file
  local report_file="$REPORTS_DIR/${run_id}_${report_id}.json"
  echo "$report" >"$report_file"

  echo "Report created: $report_id"

  # Send to configured destinations
  send_report "$report"

  echo "$report_id"
}

# Send report to destinations
send_report() {
  local report="$1"
  local destinations="${REPORT_DESTINATIONS:-$DEFAULT_DESTINATIONS}"

  IFS=',' read -ra DEST_ARRAY <<<"$destinations"

  for dest in "${DEST_ARRAY[@]}"; do
    case "$dest" in
      "file")
        # Already saved to file
        ;;
      "slack")
        send_to_slack "$report"
        ;;
      "linear")
        send_to_linear "$report"
        ;;
      "supabase")
        send_to_supabase "$report"
        ;;
      *)
        echo "Unknown destination: $dest" >&2
        ;;
    esac
  done
}

# Send report to Slack
send_to_slack() {
  local report="$1"

  local status
  local workflow
  local message
  local run_id

  status=$(echo "$report" | jq -r '.status')
  workflow=$(echo "$report" | jq -r '.workflow')
  message=$(echo "$report" | jq -r '.message')
  run_id=$(echo "$report" | jq -r '.run_id')

  # Determine emoji and color
  local emoji color
  case "$status" in
    "success")
      emoji=":white_check_mark:"
      color="good"
      ;;
    "failure")
      emoji=":x:"
      color="danger"
      ;;
    "partial")
      emoji=":warning:"
      color="warning"
      ;;
    *)
      emoji=":information_source:"
      color="#808080"
      ;;
  esac

  # Build Slack message
  local slack_payload
  slack_payload=$(
    cat <<EOF
{
    "attachments": [{
        "color": "$color",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": "$emoji Workflow: $workflow"
                }
            },
            {
                "type": "section",
                "fields": [
                    {"type": "mrkdwn", "text": "*Status:*\n$status"},
                    {"type": "mrkdwn", "text": "*Run ID:*\n$run_id"}
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "*Message:*\n$message"
                }
            }
        ]
    }]
}
EOF
  )

  # Send if webhook URL configured
  if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    curl -s -X POST "$SLACK_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$slack_payload" >/dev/null 2>&1 || {
      echo "Warning: Failed to send to Slack" >&2
    }
  else
    echo "Slack notification skipped (SLACK_WEBHOOK_URL not set)"
  fi
}

# Send report to Linear
send_to_linear() {
  local report="$1"

  local status
  local workflow
  local message
  local run_id

  status=$(echo "$report" | jq -r '.status')
  workflow=$(echo "$report" | jq -r '.workflow')
  message=$(echo "$report" | jq -r '.message')
  run_id=$(echo "$report" | jq -r '.run_id')

  # Create or update Linear issue comment
  if command -v mcp__linear__create_issue &>/dev/null; then
    echo "Would create Linear issue/comment for workflow: $workflow"
    # mcp__linear__create_issue ...
  else
    echo "Linear integration skipped (MCP not available)"
  fi
}

# Send report to Supabase
send_to_supabase() {
  local report="$1"

  # Insert into workflow_outcomes table
  if command -v mcp__supabase__execute_sql &>/dev/null; then
    local sql
    sql="INSERT INTO workflow_outcomes (report_id, workflow, run_id, status, message, metrics, created_at)
             VALUES (
                 '$(echo "$report" | jq -r '.report_id')',
                 '$(echo "$report" | jq -r '.workflow')',
                 '$(echo "$report" | jq -r '.run_id')',
                 '$(echo "$report" | jq -r '.status')',
                 '$(echo "$report" | jq -r '.message')',
                 '$(echo "$report" | jq -c '.metrics')',
                 NOW()
             )"
    echo "Would execute SQL: $sql"
    # mcp__supabase__execute_sql "$sql"
  else
    echo "Supabase integration skipped (MCP not available)"
  fi
}

# List reports for a workflow
list_reports() {
  local workflow_name="${1:-}"

  init_reports

  echo "Workflow Reports"
  echo "================"

  local pattern="*.json"
  if [[ -n "$workflow_name" ]]; then
    pattern="*_${workflow_name}_*.json"
  fi

  find "$REPORTS_DIR" -name "$pattern" 2>/dev/null | sort -r | head -20 | while read -r file; do
    local report_id
    local workflow
    local status
    local timestamp

    report_id=$(jq -r '.report_id' "$file")
    workflow=$(jq -r '.workflow' "$file")
    status=$(jq -r '.status' "$file")
    timestamp=$(jq -r '.timestamp' "$file")

    local status_icon
    case "$status" in
      "success") status_icon="✓" ;;
      "failure") status_icon="✗" ;;
      "partial") status_icon="⚠" ;;
      *) status_icon="○" ;;
    esac

    echo "  $status_icon [$status] $workflow - $report_id @ $timestamp"
  done
}

# Get report details
get_report() {
  local report_id="$1"

  local report_file
  report_file=$(find "$REPORTS_DIR" -name "*_${report_id}.json" 2>/dev/null | head -1)

  if [[ -f "$report_file" ]]; then
    cat "$report_file"
  else
    echo "Error: Report not found: $report_id" >&2
    return 1
  fi
}

# Generate summary report
generate_summary() {
  local since="${1:-24h}"

  init_reports

  local cutoff_date
  case "$since" in
    *h) cutoff_date=$(date -v-"${since%h}"H +%Y-%m-%d 2>/dev/null || date -d "-${since%h} hours" +%Y-%m-%d) ;;
    *d) cutoff_date=$(date -v-"${since%d}"d +%Y-%m-%d 2>/dev/null || date -d "-${since%d} days" +%Y-%m-%d) ;;
    *) cutoff_date="$since" ;;
  esac

  local total=0
  local success=0
  local failure=0
  local partial=0

  # Count reports on or after the cutoff date (compare the YYYY-MM-DD prefix of each
  # report's ISO timestamp). Process-substitution keeps the counters in this shell.
  while read -r file; do
    local status report_date
    status=$(jq -r '.status' "$file")
    report_date=$(jq -r '.timestamp' "$file" | cut -c1-10)
    [[ "$report_date" < "$cutoff_date" ]] && continue

    ((total++))
    case "$status" in
      "success") ((success++)) ;;
      "failure") ((failure++)) ;;
      "partial") ((partial++)) ;;
    esac
  done < <(find "$REPORTS_DIR" -name "*.json" 2>/dev/null)

  cat <<EOF
Workflow Summary Report
=======================
Period: Last $since (since $cutoff_date)

Total Runs: $total
  ✓ Success: $success
  ✗ Failure: $failure
  ⚠ Partial: $partial

Success Rate: $((total > 0 ? success * 100 / total : 0))%
EOF
}

# If run directly, provide CLI
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    report)
      report_outcome "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-{}}"
      ;;
    list)
      list_reports "${2:-}"
      ;;
    get)
      get_report "${2:-}"
      ;;
    summary)
      generate_summary "${2:-24h}"
      ;;
    *)
      echo "Outcome Reporter"
      echo ""
      echo "Usage: $0 <command> [args]"
      echo ""
      echo "Commands:"
      echo "  report <workflow> <run_id> <status> <message> [metrics]"
      echo "  list [workflow]              List recent reports"
      echo "  get <report_id>              Get report details"
      echo "  summary [period]             Generate summary (default: 24h)"
      ;;
  esac
fi
