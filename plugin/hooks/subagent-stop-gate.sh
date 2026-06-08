#!/usr/bin/env bash
# Hook: SubagentStop quality gate — CHEAP companion to stop-gate.sh
# Event: SubagentStop
# Philosophy: the parent Stop gate owns the expensive checks (tsc, git hygiene).
#   A subagent finishing should NOT pay that cost N times. This gate is grep-only:
#   it scans the subagent's OWN transcript tail for self-reported failure/incompleteness
#   and surfaces it to the orchestrator via 2.1.163 SubagentStop additionalContext —
#   so the parent learns "this worker didn't actually finish" without re-doing work.
# Loop-safe: honors stop_hook_active; never blocks (advisory only — subagents shouldn't
#   be trapped in a block/continue loop, that's the parent's job).
set +e

input=$(cat)
# Fail-open if python3 is unavailable (advisory hook — never trap the turn).
command -v python3 >/dev/null 2>&1 || exit 0
jget() { printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null; }

# --- Loop guard (accept True/true/1) ---------------------------------------
case "$(jget stop_hook_active)" in [Tt]rue|1|TRUE) exit 0;; esac

transcript=$(jget transcript_path)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# --- Cheap scan: last ~40 lines of the subagent transcript for failure signals
# Self-reported incompleteness is the single highest-signal, lowest-cost check.
tail_text=$(tail -n 40 "$transcript" 2>/dev/null)
signal=$(printf '%s' "$tail_text" | grep -oiE \
  "i was unable to|could not (complete|finish|find|resolve)|failed to [a-z]+|blocked on|ran out of|did not (complete|finish)|incomplete" \
  | head -1)

[ -z "$signal" ] && exit 0

# Advisory only — feed the orchestrator a flag, keep the turn going (no block).
note="subagent-gate: this worker's transcript tail self-reports trouble ('${signal}'). Before treating its result as complete, verify the deliverable exists on disk / the claim holds (verify-before-action)."
printf '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":%s}}' \
  "$(printf '%s' "$note" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
exit 0
