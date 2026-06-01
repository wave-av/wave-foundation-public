#!/bin/bash
# Checkpoint Manager
# Manages workflow checkpoints for state persistence and rollback
#
# Version: 1.0.0

# Checkpoint storage
CHECKPOINT_DIR="${HOME}/.claude/state/workflows/checkpoints"
MAX_CHECKPOINTS="${MAX_CHECKPOINTS:-10}"

# Initialize checkpoint directory
init_checkpoints() {
  mkdir -p "$CHECKPOINT_DIR"
}

# Generate checkpoint ID
generate_checkpoint_id() {
  echo "chkpt_$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4 2>/dev/null || echo $$)"
}

# Create a checkpoint
# Args: run_id, step_id, [state_data]
create_checkpoint() {
  local run_id="$1"
  local step_id="$2"
  local state_data="${3:-{}}"

  init_checkpoints

  local checkpoint_id
  checkpoint_id=$(generate_checkpoint_id)
  local checkpoint_file="$CHECKPOINT_DIR/${run_id}_${checkpoint_id}.json"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Create checkpoint data
  cat >"$checkpoint_file" <<EOF
{
    "checkpoint_id": "$checkpoint_id",
    "run_id": "$run_id",
    "step_id": "$step_id",
    "timestamp": "$timestamp",
    "state": $state_data,
    "environment": {
        "pwd": "$(pwd)",
        "user": "${USER:-unknown}"
    }
}
EOF

  echo "Checkpoint created: $checkpoint_id"

  # Cleanup old checkpoints
  cleanup_old_checkpoints "$run_id"

  echo "$checkpoint_id"
}

# Restore from checkpoint
# Args: checkpoint_id
restore_checkpoint() {
  local checkpoint_id="$1"

  # Find checkpoint file
  local checkpoint_file
  checkpoint_file=$(find "$CHECKPOINT_DIR" -name "*_${checkpoint_id}.json" 2>/dev/null | head -1)

  if [[ ! -f "$checkpoint_file" ]]; then
    echo "Error: Checkpoint not found: $checkpoint_id" >&2
    return 1
  fi

  # Read checkpoint data
  local run_id
  local step_id
  local state

  run_id=$(jq -r '.run_id' "$checkpoint_file")
  step_id=$(jq -r '.step_id' "$checkpoint_file")
  state=$(jq '.state' "$checkpoint_file")

  echo "Restoring checkpoint: $checkpoint_id"
  echo "  Run ID: $run_id"
  echo "  Step ID: $step_id"

  # Export state for workflow runner
  export CHECKPOINT_RUN_ID="$run_id"
  export CHECKPOINT_STEP_ID="$step_id"
  export CHECKPOINT_STATE="$state"

  echo "$state"
}

# List checkpoints for a run
# Args: run_id
list_checkpoints() {
  local run_id="$1"

  init_checkpoints

  echo "Checkpoints for run: $run_id"
  echo "========================="

  find "$CHECKPOINT_DIR" -name "${run_id}_*.json" 2>/dev/null | sort | while read -r file; do
    local checkpoint_id
    local step_id
    local timestamp

    checkpoint_id=$(jq -r '.checkpoint_id' "$file")
    step_id=$(jq -r '.step_id' "$file")
    timestamp=$(jq -r '.timestamp' "$file")

    echo "  $checkpoint_id - Step: $step_id @ $timestamp"
  done
}

# Get latest checkpoint for a run
# Args: run_id
get_latest_checkpoint() {
  local run_id="$1"

  local latest_file
  latest_file=$(find "$CHECKPOINT_DIR" -name "${run_id}_*.json" 2>/dev/null | sort -r | head -1)

  if [[ -n "$latest_file" ]]; then
    jq -r '.checkpoint_id' "$latest_file"
  fi
}

# Rollback to last checkpoint
# Args: run_id
rollback_to_last_checkpoint() {
  local run_id="$1"

  local latest_checkpoint
  latest_checkpoint=$(get_latest_checkpoint "$run_id")

  if [[ -z "$latest_checkpoint" ]]; then
    echo "Error: No checkpoints found for run: $run_id" >&2
    return 1
  fi

  echo "Rolling back to checkpoint: $latest_checkpoint"
  restore_checkpoint "$latest_checkpoint"
}

# Delete a specific checkpoint
# Args: checkpoint_id
delete_checkpoint() {
  local checkpoint_id="$1"

  local checkpoint_file
  checkpoint_file=$(find "$CHECKPOINT_DIR" -name "*_${checkpoint_id}.json" 2>/dev/null | head -1)

  if [[ -f "$checkpoint_file" ]]; then
    rm -f "$checkpoint_file"
    echo "Deleted checkpoint: $checkpoint_id"
  fi
}

# Cleanup old checkpoints (keep most recent N)
# Args: run_id
cleanup_old_checkpoints() {
  local run_id="$1"

  local checkpoint_count
  checkpoint_count=$(find "$CHECKPOINT_DIR" -name "${run_id}_*.json" 2>/dev/null | wc -l)

  if [[ $checkpoint_count -gt $MAX_CHECKPOINTS ]]; then
    local to_delete=$((checkpoint_count - MAX_CHECKPOINTS))

    find "$CHECKPOINT_DIR" -name "${run_id}_*.json" 2>/dev/null | sort | head -n "$to_delete" | while read -r file; do
      rm -f "$file"
      echo "Cleaned up old checkpoint: $(basename "$file")"
    done
  fi
}

# Cleanup all checkpoints for a run
# Args: run_id
cleanup_run_checkpoints() {
  local run_id="$1"

  find "$CHECKPOINT_DIR" -name "${run_id}_*.json" -delete 2>/dev/null
  echo "Cleaned up all checkpoints for run: $run_id"
}

# Export checkpoint to file
# Args: checkpoint_id, output_file
export_checkpoint() {
  local checkpoint_id="$1"
  local output_file="$2"

  local checkpoint_file
  checkpoint_file=$(find "$CHECKPOINT_DIR" -name "*_${checkpoint_id}.json" 2>/dev/null | head -1)

  if [[ -f "$checkpoint_file" ]]; then
    cp "$checkpoint_file" "$output_file"
    echo "Exported checkpoint to: $output_file"
  else
    echo "Error: Checkpoint not found: $checkpoint_id" >&2
    return 1
  fi
}

# Import checkpoint from file
# Args: input_file
import_checkpoint() {
  local input_file="$1"

  if [[ ! -f "$input_file" ]]; then
    echo "Error: File not found: $input_file" >&2
    return 1
  fi

  init_checkpoints

  local checkpoint_id
  local run_id

  checkpoint_id=$(jq -r '.checkpoint_id' "$input_file")
  run_id=$(jq -r '.run_id' "$input_file")

  cp "$input_file" "$CHECKPOINT_DIR/${run_id}_${checkpoint_id}.json"
  echo "Imported checkpoint: $checkpoint_id"
}

# If run directly, provide CLI
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    create)
      create_checkpoint "${2:-}" "${3:-}" "${4:-{}}"
      ;;
    restore)
      restore_checkpoint "${2:-}"
      ;;
    list)
      list_checkpoints "${2:-}"
      ;;
    latest)
      get_latest_checkpoint "${2:-}"
      ;;
    rollback)
      rollback_to_last_checkpoint "${2:-}"
      ;;
    delete)
      delete_checkpoint "${2:-}"
      ;;
    cleanup)
      cleanup_run_checkpoints "${2:-}"
      ;;
    export)
      export_checkpoint "${2:-}" "${3:-}"
      ;;
    import)
      import_checkpoint "${2:-}"
      ;;
    *)
      echo "Checkpoint Manager"
      echo ""
      echo "Usage: $0 <command> [args]"
      echo ""
      echo "Commands:"
      echo "  create <run_id> <step_id> [state_json]   Create checkpoint"
      echo "  restore <checkpoint_id>                   Restore from checkpoint"
      echo "  list <run_id>                            List checkpoints"
      echo "  latest <run_id>                          Get latest checkpoint ID"
      echo "  rollback <run_id>                        Rollback to last checkpoint"
      echo "  delete <checkpoint_id>                   Delete checkpoint"
      echo "  cleanup <run_id>                         Delete all checkpoints for run"
      echo "  export <checkpoint_id> <file>            Export checkpoint to file"
      echo "  import <file>                            Import checkpoint from file"
      ;;
  esac
fi
