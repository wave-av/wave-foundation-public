# Local Inference: Local-vs-Hosted Decision Matrix

> **When does a Claude API call NOT need Claude?** This file maps each capability to a
> local-first verdict, ties it to the [model-routing Leveragizer](../model-routing/README.md)
> (`local → gateway → openrouter → direct → human`), and names the **escalation trigger** that
> flips a call up to a hosted frontier model.
>
> The Leveragizer principle: every call starts at the cheapest tier that can *plausibly* satisfy
> it, escalating **only on structured failure** (timeout / 5xx / schema-validation fail / quality
> classifier below bar). This file is the per-capability *policy* that feeds tier-1 decisions; the
> [routing chassis](../model-routing/CHASSIS.md) is the runnable *mechanism*. Never hardcode a
> model — local OR hosted — in code.

## Two audiences, one mechanism

| Audience | Default | Identity / attribution | Escalation owner |
|---|---|---|---|
| **US** (internal humans + agents + bots) | **local** (Studio tier-1) | service account per workload class (`service_account_id`) | the agent, on structured failure |
| **OUR USERS** (customer-facing **sovereign tier**) | **local**, opt-in per tenant | workspace per tenant (`workspace_id`), **same** axes as hosted | per-tenant ZDR/quality flag |

The sovereign tier is **the same routing chassis** pointed at local with per-USER attribution: a
customer who selects "sovereign / on-prem" gets their traffic served by Studio, logged and billed
through the **identical** `usage_report`/`cost_report` path as a hosted tenant — see
[`identity-and-usage.md`](./identity-and-usage.md). Sovereign ≠ unattributed; it is *local-served,
fully-attributed*.

## The capability matrix

Studio fleet = Ollama at `http://your-ollama-host:11434` (champions.json is the single source of
truth; read it, don't memorize model names here).

| Capability | Local-capable? | Studio champion | Quality bar | Escalation trigger → hosted |
|---|---|---|---|---|
| **reasoning / codegen** | ⚠️ scan-only | `wave-qwen3-coder-30b` (code, ci_lb 0.84); `wave-deepseek-r1-32b` (reasoning, think ON ≥2000) | ci_lb ≥ 0.80 on bench axis | **new-API correctness**, schema-migration drafting, prod codegen → `claude-opus-4-8` |
| **embeddings** | ✅ yes | local embed model (Studio) | recall@k on a seeded eval set | none (stable axis); escalate only if vendor-parity required by contract |
| **classification / moderation** | ✅ yes (default) | `wave-router` (~30ms JSON), `wave-granite4` cheap-first | conformal **singleton** set | **ambiguous set** (non-singleton) → escalate the underlying task |
| **vision / PDF** | ❌ no local champion | — | n/a | **always** → `claude-opus-4-8` / `claude-sonnet-4-6` (Files API, [`files-and-media.md`](./files-and-media.md)) |
| **batch-style fanout** | ✅ yes (0-cost) | any axis champion, looped on Studio | per-item bar of the underlying axis | per-item escalation only on that item's failure |
| **tool / agent loops** | ⚠️ trivial turns only | `wave-qwen3-coder-30b` | `eval_gate dangerous==0` + tools satisfied | **multi-turn plan+act**, tool-bearing main turn → `claude-opus-4-8` |

Legend: ✅ default-local · ⚠️ local for a **narrow** sub-case, escalate otherwise · ❌ no local
champion, always hosted.

### Why reasoning/codegen is ⚠️ not ✅ — the dogfood evidence

We dogfooded this exact standard. When the Claude-API audit task was classified, **WAVE
`dispatch_route` returned `claude_reason @ 0.85`** — high confidence that the *authoring* of new
API guidance needed the frontier model, not local. We then ran the local 30B over the same
material as a check:

- The local 30B **MISSED** the load-bearing `temperature → 400` regression (Opus 4.8/4.7 reject
  sampling params with a hard 400; see [`model-matrix.md`](./model-matrix.md)). It had no current
  knowledge of the constraint and did not flag the migration hazard.
- The local 30B **DID** catch a **stale model reference** — a pure scanning/pattern task.

Conclusion, encoded in the matrix: **local is fit for scanning, not for new-API correctness.** Use
local to *find* candidates (stale aliases, grep-shaped lint, first-draft); escalate to
`claude-opus-4-8` for anything where being *wrong about the current API* costs a 400 in production.
This is exactly why `long-context` / `retrieval-grounding` / `semantic-symbolic` axes have **no
local champion** in champions.json and escalate to Claude by default (safe).

## Escalation policy (per capability)

```text
# default internal path — Leveragizer tiers 1→4
local_champion → gateway(claude_sonnet) → direct(claude_opus_4_8) → human
```

Triggers, in priority order, that bypass local **at the call site** (document the bypass — never a
silent default):

1. **Capability gap** — `vision/PDF` (no local champion) → hosted, always.
2. **Correctness-critical** — new-API codegen, schema migration, prod path → `claude-opus-4-8`.
3. **Classifier ambiguity** — conformal set is non-singleton → escalate the task it gates.
4. **Structured failure** — local timeout / 5xx / schema-validation fail → next tier.
5. **Multi-turn tool loop** — local serves trivial turns only; tool-bearing main turns pass through.

## US path (internal / agents)

Default-local. The chassis serves trivial turns (single short user message, no tools) on Studio
with **no frontier key**; tool-bearing / multi-turn turns pass through to the frontier by design.

```python
# Internal agent: classify locally, escalate to frontier only on structured failure.
from local_offload.profiles import ProfileRouter   # frameworks/model-routing chassis
router = ProfileRouter.from_file("profiles.json")   # local → Heavy(local) → Frontier(hosted)

def reason(request, call):
    # "Code" profile fronts wave-qwen3-coder-30b; falls through to Frontier on structured failure
    return router.run("Code", request, call)         # never names a model literal
```

Frontier hop, when it fires, obeys the whole model-matrix: **adaptive thinking only**, steer depth
with `output_config.effort` (default `high`; `xhigh`/`max` Opus-only), **no** `temperature` /
`top_p` / `top_k`, **no** `thinking.budget_tokens`, **no** last-assistant prefill — all 400 on
`claude-opus-4-8`. See [`model-matrix.md`](./model-matrix.md).

```python
# The escalated frontier call (chassis builds this; shown for the contract)
resp = client.messages.create(
    model=route.model,                       # routed, default claude-opus-4-8 — never inlined
    max_tokens=32000,
    thinking={"type": "adaptive"},           # 400 if {"type":"enabled","budget_tokens":N}
    output_config={"effort": "xhigh"},       # low|medium|high|xhigh|max — xhigh Opus-only
)
# Stream when max_tokens > 16000 (SDK timeout risk on long non-streaming generations).
```

## USERS path (customer-facing sovereign tier)

A tenant who selects **sovereign** routes to local with **the same identity + usage attribution as
hosted**. The workspace IS the spend-cap + attribution boundary either way.

```python
# Sovereign tenant: route locally, but stamp the SAME workspace/principal as a hosted tenant.
route = leveragizer.route(
    capability="classification",
    principal=tenant.service_account_id,     # US axis: service_account_id
    workspace_id=tenant.workspace_id,        # USER axis: per-tenant spend cap + attribution
    sovereign=tenant.sovereign,              # True → prefer local champion, same logging path
)
# usage_report / cost_report group_by workspace_id — sovereign rows attribute identically.
```

Attribution rules that hold for sovereign exactly as for hosted (from
[`identity-and-usage.md`](./identity-and-usage.md)): per-USER → group `usage_report` by
`workspace_id`; **$ per USER tenant** → `cost_report group_by workspace_id` (`1d` buckets only).
Sovereign tenants still get a workspace, still get spend caps, still appear in the cost report —
the only difference is the substrate that served the tokens.

### Caching & ZDR for sovereign

- **Prompt caching IS ZDR-eligible** — keep it on for ZDR/sovereign tenants. Verify hits via
  `usage.cache_read_input_tokens > 0`; min cacheable prefix on `claude-opus-4-8` = **1,024** (live
  doc authoritative; older cached tables said 4,096 — pad short prefixes to engage caching). See
  [`model-matrix.md`](./model-matrix.md).
- **Batch API (50% off) is NOT ZDR-eligible** — never route a ZDR/sovereign tenant's traffic
  through `/v1/messages/batches`. For sovereign **batch-style fanout**, loop the local champion on
  Studio (0-cost, stays on-prem) — that is the sovereign substitute for the hosted Batch API.

## Anti-patterns

- ❌ Defaulting reasoning/codegen to local for **new-API-correctness** work — the 30B missed the
  `temperature → 400` regression. Local scans; the frontier decides correctness.
- ❌ Routing `vision/PDF` to local — there is **no local champion**; it is always hosted.
- ❌ Trusting a local classifier on a **non-singleton** conformal set — escalate the ambiguous case.
- ❌ Serving a sovereign tenant **without** a `workspace_id` — collapses per-USER attribution; the
  cost report goes blind.
- ❌ Routing ZDR/sovereign traffic through the hosted **Batch API** (not ZDR-eligible); loop locally.
- ❌ Silent local-vs-hosted default at a bypass site — document every tier-1 bypass at the call site.
- ❌ Hardcoding any model (local or hosted) — read champions.json / route via config.
- ❌ Bypassing the gateway to hit `api.anthropic.com` directly — loses attribution + aggregation.
- ❌ Date-suffixing the alias (`claude-opus-4-8-2026...`) on the escalation hop.

## Env vars

| Var | Purpose |
|---|---|
| `OLLAMA_API_KEY` | tier-1 Studio gate (local champions at `your-ollama-host:11434`) |
| `WAVE_PROXY_OFFLOAD` | chassis offload switch; **unset = passthrough + measure** (safe default) |
| `ANTHROPIC_BASE_URL` | points at the gateway/shim — never `api.anthropic.com` directly |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 gateway — the escalation default for direct-Anthropic traffic |
| `ANTHROPIC_WORKSPACE_ID` | `wrkspc_...` — tenant/spend-cap boundary (hosted **and** sovereign) |
| `ANTHROPIC_SERVICE_ACCOUNT_ID` | `svac_...` — internal (US) principal for attribution |
| `CLAUDE_DEFAULT_MODEL` | `claude-opus-4-8` — escalation target, read by the router, never inlined |

## Curl reference (escalation hop)

```bash
# What the chassis emits when local fails the bar and escalates to the frontier:
curl https://api.anthropic.com/v1/messages \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d '{
    "model": "claude-opus-4-8",
    "max_tokens": 32000,
    "thinking": {"type": "adaptive", "display": "summarized"},
    "output_config": {"effort": "xhigh"},
    "messages": [{"role": "user", "content": "Verify this against the CURRENT API."}]
  }'
```

## Build tasks

- [#21] 0-cost local batch loop on Studio for internal evals (the sovereign Batch substitute).
- [#23] Per-user LOCAL routing (sovereign tier) for our USERS — same attribution path as hosted.
- [#22] Migrate dispatch-routing / sovereign spokes to `claude-opus-4-8` escalation + adopt this
  matrix.

## Related

- [`identity-and-usage.md`](./identity-and-usage.md) — per-user tokens + `usage_report`/`cost_report`
  attribution (the *same* path sovereign tenants use).
- [`model-matrix.md`](./model-matrix.md) — per-model frontier constraints (the 400s the local 30B
  doesn't know about).
- [`../model-routing/README.md`](../model-routing/README.md) — multi-tier Leveragizer + budget caps.
- [`../model-routing/CHASSIS.md`](../model-routing/CHASSIS.md) — runnable local-offload router/shim.
- [`../model-routing/champions.md`](../model-routing/champions.md) — champions registry + the 7-axis
  capability graph (which axes have a local champion vs escalate-to-Claude).

---

Sources (snapshot, 2026-05-30): `frameworks/model-routing/README.md`,
`frameworks/model-routing/CHASSIS.md`, `frameworks/model-routing/champions.md`,
`frameworks/model-routing/champions.json`, `frameworks/claude-api/model-matrix.md`,
`frameworks/claude-api/identity-and-usage.md`. Dogfood evidence: WAVE `dispatch_route` →
`claude_reason@0.85`; local 30B missed `temperature→400`, caught stale model ref.
