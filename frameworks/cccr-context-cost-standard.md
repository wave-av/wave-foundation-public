# CCCR Context-Cost Standard (portable, adoptable on any machine)

A drop-in bundle of 3 hooks that (a) make `/clear` task-safe, (b) auto-capture work before
compaction, and (c) surface a cost-optimal compact-vs-clear recommendation. Proven ~3× reduction in
interactive Claude Code carry cost (see `PLAN.md` / `MEASUREMENTS.md`). All paths use `$HOME` /
`$CLAUDE_*`; no machine-specific assumptions → portable as-is.

> Out of scope for this bundle: `studio-cc` (dials a specific Studio host) is a per-operator helper,
> not part of the shareable standard.

## The 3 hooks (single source of truth: `$HOME/.claude/hooks/`)

| Hook | Event | Role |
|---|---|---|
| `task-export.sh` | **Stop** + PreCompact (+ standalone) | Dump open tasks (status≠completed/deleted) from `$HOME/.claude/tasks/<sid>/` → a **per-project** store `$HOME/.claude/tasks-carryover/p_<sha1(cwd)>.json` (+`.md`). Runs on **Stop** so the store is current after *every* turn — `/clear` fires no pre-hook, so this is what makes `/clear` safe at any moment. **Keyed by cwd** (which `/clear` preserves) so concurrent sessions in different projects don't clobber a single shared file. Resolves session id from stdin→transcript basename→newest dir→arg. Always exit 0. |
| `task-carryover-restore.sh` | SessionStart | Re-materialize carried tasks into the NEW session dir **only when `source=clear`** (a plain `startup` must not inherit a carryover; compact/resume keep the id). Restores only into an empty dir; freshness-guarded (fails *closed* on a bad timestamp); leaves the store unconsumed if the new session id is missing; consume-once on success; emits a SessionStart context list as fallback. |
| `context-budget-warn.sh` | UserPromptSubmit | Read real ctx from transcript's last usage record; at SOFT/HARD bands emit per-turn re-read $ + capture nudge + compact-vs-clear recommendation with live $ math. **Post-compaction grace:** consumes the one-shot sentinel `session-start.sh` drops on `source=compact` and stays quiet for that one turn — otherwise it would read the *stale pre-compact* usage record (no fresh record exists yet) and falsely warn "approaching the band" the instant you compacted. Real floor lands next turn (~70–90k, measured). **Cache-WRITE (miss) visibility:** also reads the last turn's `cache_creation` vs `cache_read` split and flags a 🔥 miss when a warm cache (rd>cr) re-wrote ≥`WAVE_CACHE_WRITE_WARN` (30k) tokens — surfacing the cache-WRITE cost (60% of real spend, $6.25/MTok) that carry-only math hid. |
| `session-start.sh` | SessionStart | On `source=compact`, drop a session-keyed sentinel (`/tmp/claude/session-state/postcompact-<sid>`) so the decision engine can suppress that false first-turn warning. (Also carries the foundation rule reminders + shared-checkout guard.) |

### Why these three solve the `/clear`-loses-tasks fear
Tasks live at `$HOME/.claude/tasks/<SESSION_ID>/<n>.json` with **no session-lineage pointer**.
`/compact` keeps the session id → tasks survive natively. `/clear` **rotates** the id → tasks orphan.
`task-export` (kept current on every Stop) + `task-carryover-restore` (on the next `source=clear`
SessionStart) bridge that gap, so `/clear` is now task-safe at any moment. Smoke-proven 15/15.

## Install (any machine)

1. Copy the 3 scripts into `$HOME/.claude/hooks/` and `chmod +x` them.
2. Merge these entries into `$HOME/.claude/settings.json` `hooks` (order matters — export/restore run
   FIRST in their event so the capture happens before anything else):

```jsonc
"Stop": [
  { "hooks": [
    { "type": "command", "command": "bash $HOME/.claude/hooks/task-export.sh", "timeout": 10 }
  ]}
],
"PreCompact": [
  { "hooks": [
    { "type": "command", "command": "bash $HOME/.claude/hooks/task-export.sh", "timeout": 10 }
  ]}
],
"SessionStart": [
  { "hooks": [
    { "type": "command", "command": "bash $HOME/.claude/hooks/task-carryover-restore.sh", "timeout": 10 }
  ]}
],
"UserPromptSubmit": [
  { "hooks": [
    { "type": "command", "command": "bash $HOME/.claude/hooks/context-budget-warn.sh", "timeout": 15 }
  ]}
]
```

If the events already exist, append these entries to their existing `hooks` arrays (don't replace).

## Env knobs (all optional; safe defaults)

| Var | Default | Effect |
|---|---|---|
| `WAVE_CTX_MODE` | `code` | Band preset: `plan` 120/180k · `code` 250/400k · `bulk` 100/150k (SOFT/HARD). |
| `WAVE_CTX_SOFT` | per-mode | Override soft band (tokens). |
| `WAVE_CTX_HARD` | per-mode | Override hard band (tokens). |
| `WAVE_CARRYOVER_MAX_AGE` | `86400` | Carryover freshness window (s); older stores are ignored on restore. |
| `WAVE_CACHE_WRITE_WARN` | `30000` | Cache-creation tokens (warm cache) above which a 🔥 cache-miss alert fires. |

## The math (why the bands are where they are)
- Carry $/turn = ctx × cache-read-rate (Opus 0.1×input = $0.50/MTok). Growth g ≈ 1,300 tok/turn.
  Compaction floor F ≈ 70k. Cost-optimal threshold **T\* = F + √(2gK/r) ≈ 110k**, biased up per mode.
- **T\* is tier-invariant** (~110k on Haiku/Sonnet/Opus): price ratios are uniform (output = 5× input,
  cache-read = 0.1× input for all) so the input_rate cancels in K/r. Cheaper tiers only lower the
  absolute $/turn, not the optimum. (See `MEASUREMENTS.md`.)
- **Subagents have no T\***: single-shot, never compacted → run to DONE or model ceiling
  (Haiku 200k · Sonnet/Opus 1M). >150k of own context = scoping error → shard via fan-out/Workflow.

## Verify after install
```
bash $HOME/.claude/hooks/tests/cccr_smoke_task_survival.sh    # expect 15/15
bash $HOME/.claude/hooks/tests/cccr_smoke_decision_engine.sh  # expect 10/10
```
E2E (manual, definitive): TaskCreate a task → `/clear` → confirm it reappears next session.

## Companion (not a hook, but part of the regime)
`$HOME/.claude/rules/delegate-heavy-work.md` — the Opus-orchestrates / cheap-worker-does-the-tokens
reflex + Tier-0→3 model ladder. Ship alongside for the full cost regime.

## Landing it in wave-foundation (the gated step — needs Jake)
`wave-foundation` is wired as a local plugin marketplace (`settings.json` → extraKnownMarketplaces).
The bundle should land as part of that plugin (hooks + this STANDARD.md as the README), OR as a
standalone `cccr-context-cost` plugin in the same marketplace. Pick the layout, then it's a normal
foundation PR (branch-protected; PR-required). This doc is the ready-to-drop payload.
