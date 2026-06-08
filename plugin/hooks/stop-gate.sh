#!/usr/bin/env bash
# Foundation Stop gate (graduated from operator install 2026-06-05).
# Leverages CC 2.1.163: Stop `additionalContext` feeds Claude and KEEPS THE TURN
#   GOING without being labeled a hook error — used for *discipline* nudges
#   (never-done, hygiene); the `decision:block` form is reserved for *correctness*
#   failures (type errors). Loop-safe: honors `stop_hook_active` so neither a block
#   nor a keep-going can loop forever (CC caps Stop blocks at 8; this fires once).
# Portable: no external paths; only python3/git/npx (all optional-guarded).
set +e

input=$(cat)
# Fail-open if python3 is unavailable: jget can't parse, so we can't evaluate the
# loop guard safely — never block in that state (advisory portability guarantee).
command -v python3 >/dev/null 2>&1 || exit 0
jget() { printf '%s' "$input" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null; }

# --- Loop guard (CRITICAL) — accept True/true/1 defensively ----------------
case "$(jget stop_hook_active)" in [Tt]rue|1|TRUE) exit 0;; esac

transcript=$(jget transcript_path)
notes=""; blockers=""

# --- Gate 1: VERIFICATION (correctness) — hard block on type errors --------
if [ -f tsconfig.json ] && command -v npx >/dev/null 2>&1; then
  # grep -c always prints a count (0 when none) and exits 1 on zero matches; do NOT
  # add `|| echo 0` — that yields a two-line "0\n0" and breaks the -gt comparison.
  n=$(npx tsc --noEmit 2>&1 | grep -c "error TS"); n=${n:-0}
  [ "$n" -gt 0 ] 2>/dev/null && blockers="${blockers}TypeScript errors: ${n}. "
fi

# --- Gate 2: NEVER-DONE (discipline) — soft nudge --------------------------
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  closure=$(grep -oiE '(clos(e|es|ed)|fix(es|ed)?|resolv(e|es|ed)) #[0-9]+|WAVE-[0-9]{3,}' "$transcript" 2>/dev/null | head -1)
  followup=$(grep -oiE 'follow-?ups? (filed|identified)|no follow-?ups identified' "$transcript" 2>/dev/null | head -1)
  if [ -n "$closure" ] && [ -z "$followup" ]; then
    notes="${notes}never-done: this session referenced closing work ('${closure}') but no follow-ups were declared. File follow-ups OR state 'no follow-ups identified after audit' before stopping. "
  fi
fi

# --- Gate 3: HYGIENE (informational) — uncommitted tracked files -----------
if git rev-parse --is-inside-work-tree &>/dev/null; then
  dirty=$(git status --porcelain 2>/dev/null | grep -v '\.DS_Store' | grep -v '^??' | wc -l | tr -d ' ')
  [ "$dirty" -gt 0 ] && notes="${notes}${dirty} uncommitted tracked file(s) in $(basename "$(git rev-parse --show-toplevel 2>/dev/null)"). "
fi

# --- Emit ------------------------------------------------------------------
if [ -n "$blockers" ]; then
  printf '{"decision":"block","reason":%s}' "$(printf '%s' "${blockers}Fix before stopping." | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  exit 0
fi
if [ -n "$notes" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":%s}}' \
    "$(printf '%s' "$notes" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  exit 0
fi
exit 0
