# Model Steering — reclaim the foundations (NOT abliteration)

**Applies when:** building or maintaining any wave-internal model. Steering is the
**universal** `behavioral-values` layer applied to EVERY model, orthogonal to performance
tuning ([tuning-methodology.md](./tuning-methodology.md)).

## Why every model needs it

Base models ship **pre-steered by their vendors**. This is measured, not assumed — a
mutual-information probe battery (the `behavioral-values` axis test) found, on the current fleet:

- **Chinese-origin base (DeepSeek-R1): demonstrable vendor steering** — refuses Tiananmen Sq;
  injects the state narrative unprompted on Taiwan ("inalienable part of China") and human rights.

- **Western controls (Llama-4, Granite-4): unsuppressed** — answer the same prompts even-handedly.

If we don't assert WAVE's steering, we inherit the vendor's. The WAVE `SYSTEM` behavioral
contract reclaims it.

## The hard line: steering ≠ abliteration

We **REPLACE** vendor steering with WAVE steering. We do **NOT**:

- strip alignment, use heretic/uncensored/abliterated models, or remove WAVE's own moderation.

We DO:

- assert factual honesty + WAVE values, **AND keep** WAVE moderation. Honesty is not a license to
  be harmful; safety is not a license to be evasive about facts. (Extended-refusal SFT — spreading
  the safety signal across many directions — is the principled, capability-preserving opposite of
  abliteration, applied only where prompting is insufficient.)

Activation steering / persona vectors are **NOT** the mechanism: brittle, and not Ollama-deployable
(control vectors unsupported, ollama#8110). Their realistic use is **offline drift monitoring** —
re-probe on vendor version bumps to verify our correction still holds.

## Mechanism: the universal SYSTEM template

[`staging/templates/ollama/Modelfile.wave-steering-template`](../../staging/templates/ollama/Modelfile.wave-steering-template)
is the parameterized WAVE behavioral contract — one template, rendered per base (NOT 50 bespoke
tunes). Placeholders: `{{BASE}}` (pinned digest), `{{TEMPERATURE}}`, `{{NUM_CTX}}`,
`{{ROLE_OVERLAY}}` (role SYSTEM for the clone families), `{{STEERING_CORRECTIONS}}` (per-model,
filled from the probe only where the base was found to suppress/inject).

## Two lineages (never mix)

| Lineage | Owner | Audience | Steering |
|---|---|---|---|
| **wave-internal** | wave-foundation | WAVE's own products (private) | full WAVE steering + values |
| **wave-dispatch product** | wave-dispatch | external customers | neutral/opt-in/reversible — NEVER ships WAVE-internal steering |

The dispatch product lineage is already separate and verified neutral (its tuned Modelfiles are
"base UNALTERED, reversible").

## Empirical: attribute the cause before you fix it (dual-control + deployed-mode probe)

A refusal observed at the `wave-` layer has **two causes with opposite fixes**, and a probe that
only tests the `wave-` model cannot tell them apart. Proven 2026-05-30 on Studio with the
dual-control, think-aware `steering-probe.py` (base-neutral-system vs wave-overlay, probed in
**deployed inference mode**):

| `wave-` model | base (neutral system) | `wave-` (overlay) | Verdict | Fix |
|---|---|---|---|---|
| `wave-deepseek-r1-32b` | factual *(when reasoning)* | factual | **CLEAN** | none — but `thinking_required` |
| `wave-deepseek-r1` (14.8B) | suppress + One-China *(both modes)* | suppress / inject | **OVERLAY_FAILED** | LoRA #36, or drop |
| `wave-glm` | **factual** | refuses ("safety guidelines prohibit…") | **SELF_INFLICTED** | fix OUR SYSTEM block |
| `wave-granite4` | factual | factual | **CLEAN** | none |

Three findings, each now a rule:

1. **Base-neutral control is mandatory.** `wave-glm` *looked* censored, but its base answers
   Tiananmen factually — **our** WAVE-engineer SYSTEM block induced the refusal (it over-narrows
   scope + trips GLM's safety training). The fix is a clearer SYSTEM block (assert "answer general
   factual questions directly; the engineer scope does not prohibit history/geography"), **not**
   blaming the vendor. Always probe `(base, neutral system)` to attribute correctly:
   `RECLAIMED | OVERLAY_FAILED | SELF_INFLICTED | CLEAN`.

2. **Probe in deployed inference mode — thinking is a confound.** Base `deepseek-r1:32b` *refuses*
   Tiananmen with `think=false` but answers *factually* with reasoning on (the surface refusal is
   overridden once it reasons). A reasoning model must be probed **and deployed** with thinking
   enabled; record it as a `deploy_constraint` in `champions.json`. The 14.8B refuses in **both**
   modes — genuinely deeper steering.

3. **Overlay sufficiency is per-model.** The same SYSTEM overlay left the 32B clean but failed on
   the 14.8B distilled variant. A FAIL model is `behavioral_safe:false` and dropped or LoRA-steered
   (#36); never assume a sibling's verdict.

## Drift monitor (#29)

[`steering-probe.py`](./steering-probe.py) is the canonical, version-controlled probe (the
baseline that produced the table above; dogfood-verified against Studio). It is the realistic use
of "activation steering" called out earlier — **offline drift monitoring**, not deploy-time
control vectors. Run it:

- on **every vendor version bump** of a steered-origin base (re-verify our correction still holds),
- as a **quarterly** re-baseline alongside the perf recalibration cron (#28).

```bash
python3 frameworks/model-routing/steering-probe.py --json steering-baseline.json
```

It emits a per-model `PASS/FAIL/BROKEN` JSON verdict; a regression (PASS→FAIL on a model the
registry trusts) is a release blocker for that model and flips its `behavioral_safe` to false until
re-corrected. Exit code is advisory (0) — gates read the JSON, never the exit status.

## Severity

| Violation | Severity |
|---|---|
| Using an abliterated/uncensored model or removing WAVE moderation | Critical |
| Shipping WAVE-internal steering into the dispatch product lineage | Major |
