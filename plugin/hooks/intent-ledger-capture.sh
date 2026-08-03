#!/usr/bin/env bash
# governance: enforces=every-commitment-captured-to-the-intent-ledger; triggers-on=agent-turn:turn-end
# PreCompact — MECHANICALLY capture user asks + assistant commitments/decisions to the durable
# intent ledger BEFORE the summary compresses them away. This does NOT depend on the agent
# remembering to scan; it parses the transcript file itself (both roles). FOR THE AGENT.
#
# Reads the hook stdin JSON ({session_id, transcript_path}) and pipes it to `intent-ledger.mjs
# --capture`, which resolves the transcript, extracts + dedupes, and appends new open items.
# Then --surface prints the open list so the agent reconciles before compacting.
#
# FLEET: this is the wave-foundation plugin copy. The ledger defaults to the MACHINE-level path
# ~/.claude/state/intent-ledger.jsonl (the agent's cross-session memory) — never a consumer repo.
#
# Rollout: capture + surface always run (guaranteed, nothing leaks). The HARD block is opt-in via
# INTENT_LEDGER_BLOCK=1 (shadow-before-enforce) so a large historical backlog can't wedge a live
# compaction. Ramp to --block after it is proven non-wedging across the fleet.
set -u
LEDGER_BIN="${CLAUDE_PLUGIN_ROOT}/hooks/intent-ledger.mjs"
[ -f "$LEDGER_BIN" ] || exit 0
command -v node >/dev/null 2>&1 || exit 0

stdin_json="$(cat 2>/dev/null || true)"
printf '%s' "$stdin_json" | node "$LEDGER_BIN" --capture 2>/dev/null || true
node "$LEDGER_BIN" --surface 2>/dev/null || true

if [ "${INTENT_LEDGER_BLOCK:-0}" = "1" ]; then
  if ! node "$LEDGER_BIN" --block >/dev/null 2>&1; then
    echo "⛔ intent-ledger: unreconciled action items remain — TaskCreate or dismiss them before compacting." >&2
    exit 2 # block signal (honored where the harness supports PreCompact veto)
  fi
fi
exit 0
