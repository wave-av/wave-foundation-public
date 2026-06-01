# Model Tuning & Selection Methodology

**Applies when:** benching, tuning, selecting, or calibrating any local model that populates
the [model-routing](./README.md) tiers. This is the canonical, evidence-first methodology —
every repo inherits it instead of re-deriving "which model / how tuned" by vibes.

**Core principle:** the rigor already exists, proven, in `wave-av/wave-dispatch`. This doc
lifts it out of that silo into the standard. Each routing/tuning decision has a principled
method and a named reference implementation; the naïve baseline we REJECT is named so no
spoke regresses to it.

## Decision → principled method (reject the naïve baseline)

| Decision | Naïve (REJECT) | Principled method | Reference impl (wave-dispatch) |
|---|---|---|---|
| "what is good?" | plain accuracy | cost-**asymmetric** loss; under-escalation ≫ over-escalation ≫ lateral; `dangerous→0` | `route_metric.py` |
| escalate to frontier? | `confidence > 0.7` | expected-cost minimization → derived breakeven success-prob | `cost_decision.py` |
| classifier sure enough? | `margin ≥ 0.2` | **split-conformal** prediction → coverage guarantee ≥ 1−α (singleton set = fast-path) | `conformal.py` |
| confidence signal | self-report (miscalibrated) | self-consistency agreement (sample N, agreement = calibrated) | `sc_confidence.py` |
| which model per axis? | static hand-map | **Thompson-sampling bandit** (Beta-Bernoulli, online) | `bandit.py` |
| leaderboard | toy-prompt vibes | cost-aware: cheapest model that PASSES, with rationale | `learn_loop.py` |
| bench honesty | one number on all data | debiased held-out eval (kills synthetic inflation) | `debias_eval.py`, `lora_heldout.py` |
| stay calibrated | periodic full retrain | online `partial_fit` + drift tracking on REAL traffic | `online_learn.py` |
| serving capacity | guess `NUM_PARALLEL` | M/M/c Erlang-C (derive slots, spill, utilization) | `queueing.py` |
| prompt tuning | hand-edit | **GEPA** reflective evolution (Pareto frontier; beats GRPO at fraction of rollouts) | `router_gepa.py` |
| regression safety | hope | invariant gate: assert `dangerous==0` every run, exit nonzero | `eval_gate.py`, `edge_calibration.py` |

## Method-family lineage (math / physics / bio)

- **Math** — Bayesian decision theory (`cost_decision`), statistical-learning guarantees
  (`conformal` coverage, `lora_heldout`/`debias_eval` honest generalization), constrained
  optimization (`learn_loop` cheapest-that-passes).

- **Physics** — control theory (the recalibration loop is a closed-loop controller; verdict-delta
  = error signal; needs hysteresis to avoid champion thrash), queueing theory (`queueing.py`
  M/M/c), information theory (router entropy → escalate; MI → steering-probe design).

- **Bio** — evolutionary computation (`router_gepa` = selection on prompts w/ Pareto frontier),
  explore/exploit bandit (optimal foraging), the eval-gate invariant as an immune antibody.

## Five guards (mandatory on every champion seal)

1. **CI lower-bound selection** — champion = `argmin(cost) s.t. ci_lb(quality) ≥ bar` (Wilson/
   bootstrap). Never crown a noisy point-estimate max. (At small n, *nobody* clears → get more data.)

2. **Recalibration hysteresis** — swap incumbent→challenger only if it beats by a margin > noise
   band, sustained over k windows, with cooldown. Prevents thrash.

3. **MI-designed steering probes** — see [steering.md](./steering.md); maximize discrimination.
4. **Frozen designed experiment** — fixed seed/split, stratified REAL-traffic sampling, eval on
   curated non-templated held-out only, report CIs, freeze the eval set before tuning (anti-p-hack).

5. **One cost+risk scale** — express $ and mistake-risk in the same `route_metric` units so
   selection, escalation, and calibration optimize one objective.

## What to apply where (from current SOTA, 2025–26)

- Adopt long-CoT **distilled** reasoning bases (consume the RL; don't self-run GRPO/RLVR).
- **GEPA / MIPROv2** for per-axis system-prompt optimization — prompt-tier, single-machine.
- **Grammar/JSON-constrained decoding** for all tool-use/structured paths.
- **LoRA SFT** only where held-out proves lift (Ollama `ADAPTER` for Llama/Mistral/Gemma; merge
  to GGUF for Qwen3/MoE). Pin exact base digests — the adapter base must match.

- Calibrate on REAL traffic only (synthetic inflates — dispatch saw 92.5% synth vs 68–80% real).

## GEPA loop (canonical — dispatch-proven)

Prompt-tier optimization. Reflective evolutionary search over the per-axis SYSTEM prompt; **no
weight updates**, single-machine, the cheapest 90%-of-the-value tuning lever.

1. **Seed** the axis SYSTEM prompt; freeze the held-out eval set (the #40 frozen-experiment bench).
2. **Mutate** via reflection: the model critiques its own failures on a minibatch and proposes
   prompt edits (Pareto-style: keep variants that win on *some* trace, not just mean).
3. **Score** each candidate on held-out with the cost-asymmetric `route_metric` (#41), not raw acc.
4. **Accept** only on a **CI-lower-bound** improvement (Wilson/bootstrap, #37) — never a point gain.
5. **Band gate:** only run GEPA on axes whose champion sits in the **0.50–0.80** improvable band;
   below 0.50 the base is wrong (swap it), above 0.80 returns are marginal (stop — don't overfit
   the held-out set).
Output: an evolved SYSTEM block per axis, version-pinned into the champion's Modelfile.

## Escalation ladder (canonical — dispatch-proven)

Cheapest-that-passes routing, expressed in `champions.json` as `escalation_ladder` (see the
quantitative-reasoning axis for a worked example: granite4 → r1 → r1-32b).

- **Order rungs by cost** (latency·$), not by accuracy — climb only on a fail signal.
- **Expected-cost decision** (`cost_decision`): escalate when `P(rung fails)·cost(escalation) <
  cost(serving a wrong answer)`. Calibrate `P(fail)` from real-traffic verdicts, not priors.
- **Fail-safe terminus:** the last rung is always the frontier fallback (`escalate_to`,
  e.g. claude) — the ladder never dead-ends on a local model.
- **Dangerous==0 invariant:** a rung that ever emits a dangerous output is removed from the ladder
  regardless of accuracy (eval-gate, #41).
- **Behavioral gate:** a rung with `behavioral_safe:false` (steering-FAIL, per steering.md) is
  skipped for any values/semantic/political content — admissible only for orthogonal workloads
  (e.g. math). See the 14.8B deepseek rung.

## BYOL (bring-your-own-LoRA) — DEFERRED to #36

LoRA SFT is admissible **only where a held-out set proves lift** (debiased, `lora_heldout`). The
Ollama deploy path (`ADAPTER` for Llama/Mistral/Gemma; merge-to-GGUF for Qwen3/MoE; exact
base-digest pin) is **not yet empirically validated on our Studio** — the #36 spike owns that.
Until #36 returns a verified ADAPTER round-trip, this section is a pointer, not a protocol: do not
ship a BYOL model on an unvalidated path.

## Severity

| Violation | Severity |
|---|---|
| Crowning a champion without ci_lb / on synthetic eval | Major |
| Routing without the cost-asymmetric objective + fail-safe escalate | Major |
