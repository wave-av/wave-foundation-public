#!/usr/bin/env bash
# governance: enforces=every-commitment-captured-to-the-intent-ledger; triggers-on=agent-turn:dispatch
# SessionStart — re-inject open intent-ledger items into the agent's context after every /compact
# or /clear, so decided-but-not-done work (from EITHER role) is never invisible post-compaction.
# FLEET: wave-foundation plugin copy; reads the machine-level ledger (~/.claude/state/…).
# Read-only; always exits 0.
set -u
LEDGER_BIN="${CLAUDE_PLUGIN_ROOT}/hooks/intent-ledger.mjs"
[ -f "$LEDGER_BIN" ] || exit 0
command -v node >/dev/null 2>&1 || exit 0
node "$LEDGER_BIN" --surface 2>/dev/null || true
exit 0
