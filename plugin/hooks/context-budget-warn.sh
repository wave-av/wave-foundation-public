#!/usr/bin/env bash
# UserPromptSubmit hook — context-budget decision engine (CCCR Phase 2).
# Reads the REAL current context size from the transcript's last usage record and, as it approaches
# the cost-optimal compaction band, emits: (1) the per-turn re-read $ cost, (2) a capture nudge, and
# (3) a compact-vs-clear recommendation with the $ math.
#
# MATH (measured, ~/.claude/plans/claude-cost-reduction/): carry $/turn = ctx × $0.50/MTok (Opus
# cache-read). Growth g≈1,300 tok/turn. Compaction floor F≈70k. Cost-optimal threshold
# T* = F + √(2·g·K/r) ≈ 110k, with an upward bias for fidelity per task mode.
#
# Mode-aware bands (override per session with WAVE_CTX_MODE = plan | code | bulk):
#   plan  → SOFT 120k / HARD 180k   (state already in memory+tasks; cheap to compact)
#   code  → SOFT 250k / HARD 400k   (keep tool-history fidelity; default)
#   bulk  → SOFT 100k / HARD 150k   (prefer /clear between independent items)
# Explicit WAVE_CTX_SOFT / WAVE_CTX_HARD override everything.
set -u
input="$(cat)"
tp="$(printf '%s' "$input" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("transcript_path",""))
except Exception: print("")' 2>/dev/null)"
[ -f "$tp" ] || exit 0

# Post-compaction grace (one-shot). session-start.sh (source=compact) dropped a session-keyed
# sentinel. On this first post-compact prompt, no fresh usage record exists yet, so the transcript's
# "last usage" is still the big PRE-compact value → a band warning here is a false alarm (the floor
# is really ~70–90k). Consume the sentinel and stay quiet for exactly this turn; next turn reads true.
sid="$(basename "$tp" .jsonl)"
sentinel="/tmp/claude/session-state/postcompact-$sid"
if [ -n "$sid" ] && [ -f "$sentinel" ]; then
  rm -f "$sentinel" 2>/dev/null
  echo "✅ Post-compaction: context reset to the floor (~70–90k). Any high token reading shown this turn is the stale pre-compact value; the true size lands next turn."
  exit 0
fi

# Parse the last usage-bearing record → "ctx read creation". read/creation feed the cache-miss
# visibility check (#97); ctx feeds the band logic.
usage="$(python3 - "$tp" <<'PY' 2>/dev/null
import json, sys
ctx = rd = cr = 0
with open(sys.argv[1]) as f:
    for line in f:
        try: o = json.loads(line)
        except Exception: continue
        u = (o.get("message") or {}).get("usage") or o.get("usage") or {}
        if u:
            r = u.get("cache_read_input_tokens",0) or 0
            c = u.get("cache_creation_input_tokens",0) or 0
            t = (u.get("input_tokens",0) or 0) + r + c
            if t: ctx, rd, cr = t, r, c
print(ctx, rd, cr)
PY
)"
ctx="${usage%% *}"; rest="${usage#* }"; rd="${rest%% *}"; cr="${rest##* }"
case "$ctx" in ''|*[!0-9]*) exit 0 ;; esac
case "$rd" in ''|*[!0-9]*) rd=0 ;; esac
case "$cr" in ''|*[!0-9]*) cr=0 ;; esac
[ "$ctx" -gt 0 ] || exit 0

# --- Cache-WRITE (miss) visibility (#97) — the dominant, previously-invisible cost ---
# Cache creation costs $6.25/MTok = 12.5× a $0.50 read. A normal turn re-writes only the small delta.
# A big cache_creation spike = an already-cached prefix chunk INVALIDATED + re-written (dashboard's
# *_changed misses) or expired (5-min TTL). Flag only when there was ALSO a substantial cache READ
# (rd > cr) — distinguishes a mid-session invalidation (warm cache, waste) from a legitimate
# cold/post-compact establishment (cold cache, rd≈0). Threshold via WAVE_CACHE_WRITE_WARN.
WWARN="${WAVE_CACHE_WRITE_WARN:-30000}"
if [ "$cr" -ge "$WWARN" ] && [ "$rd" -gt "$cr" ]; then
  wk=$(( cr / 1000 ))
  wcost="$(awk "BEGIN{printf \"%.3f\", $cr*6.25/1000000}")"
  echo "🔥 CACHE MISS last turn: ~${wk}k tokens RE-WRITTEN (~\$${wcost} at \$6.25/MTok = 12.5× a read). A warm-cache invalidation, not carry. Likely: a huge tool output rewrote history ('Messages changed'), a mid-session tool/skill load ('Tools changed'), or >5-min idle (TTL expiry). Cut it: route big reads/outputs to a subagent, front-load tools, don't idle mid-thread."
fi

mode="${WAVE_CTX_MODE:-code}"
case "$mode" in
  plan) dsoft=120000; dhard=180000 ;;
  bulk) dsoft=100000; dhard=150000 ;;
  *)    dsoft=250000; dhard=400000 ;;   # code (default)
esac
SOFT="${WAVE_CTX_SOFT:-$dsoft}"
HARD="${WAVE_CTX_HARD:-$dhard}"

k=$(( ctx / 1000 ))
cost="$(awk "BEGIN{printf \"%.3f\", $ctx*0.5/1000000}")"
# $ that compacting back to ~70k would save per turn
save="$(awk "BEGIN{s=($ctx-70000)*0.5/1000000; printf \"%.3f\", (s>0?s:0)}")"

if [ "$ctx" -ge "$HARD" ]; then
  echo "⚠️ CONTEXT ~${k}k (mode=$mode, HARD). Re-reading ~\$${cost}/turn; compacting→~70k saves ~\$${save}/turn. ACT NOW:
  • Continuing this thread → /compact (keeps the gist; tasks survive automatically).
  • Done / switching topic → /clear (\$0, leaner floor; your open tasks are auto-saved to the carryover store and restored next session, so they will NOT be lost).
  First: TaskCreate any unfinished plan/idea/edge-case not already tracked, and persist durable facts to memory."
elif [ "$ctx" -ge "$SOFT" ]; then
  echo "ℹ️ Context ~${k}k (mode=$mode, ~\$${cost}/turn). Approaching the compaction band — capture pending plans/ideas/edge-cases via TaskCreate soon. Then /compact (continue) or /clear (done; tasks are carryover-protected) to cut the per-turn re-read tax (~\$${save}/turn)."
fi
exit 0
