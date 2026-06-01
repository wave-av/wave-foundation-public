# Model Routing

Five-tier escalation for any AI inference call. Implements the **Token Leveragizer** principle: every call starts at the cheapest tier that can plausibly satisfy it and only escalates on explicit failure or quality signal.

| Tier | Substrate | When to use | Cost | Latency |
|------|-----------|-------------|------|---------|
| **1. Local** | Mac Studio (granite4/30B via Ollama at `100.92.89.55:11434`) | Default for all internal/agent traffic; classification; embeddings; first-draft work | ~$0 marginal | LAN-local, p50 < 200ms |
| **2. Vercel AI Gateway** | `VERCEL_AI_GATEWAY_API_KEY` | When local can't satisfy; provides rate-limiting + observability over multiple providers | metered, ~30% margin vs direct | p50 < 500ms |
| **3. OpenRouter** | Active fallback when Gateway is unavailable | Multi-provider redundancy | metered | p50 < 800ms |
| **4. Direct API** | `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | When gateway/router is down OR when feature requires a model not in gateway catalog | direct provider rates | p50 < 800ms |
| **5. Human escalation** | PagerDuty + Slack | When all model tiers fail AND task is user-blocking | engineer time | minutes |

## Default escalation policy

```text
local_30b -> gateway_claude_sonnet -> direct_anthropic_opus -> human
```

Each step is taken only on **structured failure** of the previous: timeout, 5xx, schema-validation failure of the response, or quality classifier below threshold (when a classifier exists).

> **Division of labor with [`frameworks/claude-api`](../claude-api/README.md):** this framework owns
> *which* model/tier serves a call and *when* to escalate. Once a call lands on a hosted Claude tier
> (gateway/direct), **how** the request is shaped — Opus 4.8/4.7 drop `temperature`/`top_p`/`top_k`
> and `budget_tokens` (HTTP 400), steer via `thinking:{adaptive}` + `output_config.effort`, current
> API version, streaming, caching — is governed by the claude-api standard ([`model-matrix.md`](../claude-api/model-matrix.md)),
> enforced fleet-wide by the `claude-api-shape` gate. The chassis's `AnthropicEngine` is the reference
> implementation of those rules. Sovereign/local tiers are the same chassis with the frontier hop disabled.

## Local-Offload Chassis (runnable implementation of tiers 1→4)

[`CHASSIS.md`](./CHASSIS.md) + [`local_offload/`](./local_offload/) ship the **runnable** chassis: a
declarative named-profile router (`Fast/Expert/Heavy/Code` + `local→Heavy→frontier` fallback), a
multi-frontend drop-in shim (Anthropic `:8088` / OpenAI `:8090` / Ollama `:11434`) so Claude
Code / Cursor / Cline connect unmodified, and the `cost_decision` + `cascade` escalation policies.
Pure-stdlib, additive, **opt-in-by-import**; passthrough-by-default + fail-safe. See `CHASSIS.md` to
consume it in a spoke and `local_offload/examples/e2e-smoke.sh` to dogfood it.

## When to bypass tier 1

- Tool-use chains where the local model is known-incapable (verified via eval gate)
- Customer-facing realtime where p50 < 200ms is required AND the call needs reasoning depth
- Programmatic-correctness-critical paths (codegen for production; schema migration drafting)

Document the bypass in the call site — never as silent default.

## Budget caps

- Per-request token cap: declared in the call config; the wrapper enforces it before tier 2.
- Per-tenant daily cap: enforced at gateway via [spend-authorities](../../docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md).
- Per-app monthly cap: alerts to Slack at 80%; hard stop at 100% unless explicit override.

## Anti-patterns

- ❌ Calling direct Anthropic/OpenAI without going through tier 2 first (loses observability, billing aggregation, retry policy)
- ❌ Hardcoding model name in code instead of routing config
- ❌ Hand-rolled retries with provider SDK (use the gateway's retry semantics)

## Env vars

| Var | Purpose |
|-----|---------|
| `VERCEL_AI_GATEWAY_API_KEY` | tier 2 |
| `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` | tier 4 fallback |
| `OLLAMA_API_KEY` | tier 1 (Mac Studio gate) |
| `NEXT_PUBLIC_PERPLEXITY_ENABLED` | feature flag for client-side Perplexity search |

## Which models, how tuned (the other half of routing)

The tiers above are the *escalation* mechanism. These define **which** models populate tier 1
and **how** they are tuned/selected/steered — the single source of truth the chassis + dispatch read:

- [`champions.md`](./champions.md) — champions registry + 7-axis capability graph (interchangeable / dependent / composable); `champions.json` schema + consolidation (bases + overlays) + anti-drift digest pinning.
- [`tuning-methodology.md`](./tuning-methodology.md) — evidence-first bench/select/calibrate methodology lifted from wave-dispatch (cost-asymmetric loss, conformal, bandit, GEPA, CI-lower-bound selection, the 5 guards).
- [`steering.md`](./steering.md) — the universal WAVE behavioral-values layer (reclaim vendor steering; steering ≠ abliteration; two lineages). Includes the per-model overlay-sufficiency finding + the [`steering-probe.py`](./steering-probe.py) drift monitor (#29).
- [`recalibration.md`](./recalibration.md) — quarterly + event-driven re-seal that keeps champions honest (perf bench + drift probe, hysteresis re-crown, PR-gated). Twin of the steering drift monitor.
- [`modelfile-registry.json`](./modelfile-registry.json) — #17 verified registry: deployed `manifest_id` vs `base_digest` per champion (deployed==source attestation, dispatch-#83 pattern), pulled live from Studio. Distinguishes the two digest classes (caught a real devstral2 drift) + flags the 2 arch-blocked broken models.

## Related

- [`rules/sandbox-execution.md`](../../rules/sandbox-execution.md) — generated code MUST run in sandbox
- [`docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md`](../../docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md) — spend authorities feed the budget caps
