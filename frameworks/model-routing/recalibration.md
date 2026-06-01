# Recalibration — keep champions honest over time (#28)

**Applies when:** scheduling or modifying the periodic re-evaluation that decides whether a
`champions.json` entry is still the right pick. Twin of the steering drift monitor
([steering.md §Drift monitor](./steering.md), #29): that one guards *behavior*, this one guards
*performance + cost*.

## Why a cadence (and not continuous)

Champions drift for three reasons: vendor base version bumps, real-traffic distribution shift, and
new models entering the fleet. But re-crowning on every wobble causes **thrash** (route flapping,
cache churn, attestation noise). The recalibration cadence + the **hysteresis guard (#38)** are
what convert noisy signal into a stable decision.

## Two inputs (both required for a real re-seal)

| Input | Source | Ready? |
|---|---|---|
| **Frozen-bench re-eval** | `bench_real.py` against the #40 frozen held-out set (GSM8K/HumanEval/…), Wilson `ci_lb` | now |
| **Real-traffic verdicts** | dispatch verdict-delta export (#22) — actual production pass/fail/cost per axis | when #22 lands |

Until #22 is wired, the cron runs on the frozen bench alone and **labels the result
`calibration:real-frozen`, not `calibration:real-traffic`** — do not overclaim (the same honesty
rule that downgraded the pilot seed). Synthetic-only is never an input (it inflated 92.5% vs 68–80%
real in dispatch).

## Cadence

- **Quarterly** full re-seal (perf bench + drift probe together — they share the frozen harness).
- **Event-driven** on any steered-origin **vendor version bump**: run the drift probe (#29)
  immediately; run the perf bench for the affected axis.

## Re-crown decision (hysteresis — #38)

A challenger replaces the incumbent champion only if **all** hold:

1. **Margin:** challenger `ci_lb` exceeds the incumbent's by ≥ a dead-band `δ` (not just point acc).
   `δ` damps measurement noise — a tie or marginal win keeps the incumbent (incumbency advantage).
2. **Persistence:** the challenger wins **two consecutive** recalibration cycles (anti-flap).
3. **Cost non-regression:** if accuracy is within `δ`, prefer the **cheaper** model (the cost-aware
   tiebreak that picked qwen3-coder-30b over wave-coder).
4. **Invariants intact:** challenger passes the dangerous==0 eval-gate AND `steering_verified` is
   not FAIL for any axis carrying values/semantic content.

A re-crown writes a new `champions.json` with bumped `version` + `calibrated_at`, and the old
champion is demoted to the escalation ladder (not deleted — it stays a warm fallback).

## Cron contract (stub — wire in the consuming runtime, e.g. dispatch/Inngest)

```text
id:          model-routing/quarterly-recalibration
schedule:    quarterly (+ event hook on vendor-version-bump)
concurrency: 1            # never overlap a re-seal
idempotency: quarter key  # one re-seal per period
steps:
  1. perf      = bench_real.py  --frozen  --json perf.json
  2. steering  = steering-probe.py --json steering.json
  3. verdicts  = (when #22) pull dispatch real-traffic verdict-delta
  4. decide    = apply hysteresis (#38) over {incumbent, challengers}
  5. if re-crown: open a PR bumping champions.json (NEVER auto-merge — human/gov gate)
```

The cron **proposes** via PR; it never silently mutates the registry — same governance posture as
every other foundation change.

## Compound with

- [tuning-methodology.md](./tuning-methodology.md) — the five guards (esp. #37 ci_lb, #38 hysteresis, #40 frozen bench)
- [steering.md](./steering.md) — #29 drift probe shares the cadence + frozen harness
- `champions.json` — the artifact this keeps honest

## Severity

| Violation | Severity |
|---|---|
| Re-crowning without hysteresis (margin + persistence) | Major (causes route thrash) |
| Labeling a frozen-bench-only re-seal as `real-traffic` | Major (overclaim) |
| Cron auto-merging a champion change without governance gate | Critical |
| Skipping the dangerous==0 / steering_verified invariant check on a challenger | Critical |
