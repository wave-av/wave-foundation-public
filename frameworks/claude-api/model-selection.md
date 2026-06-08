# Claude Model Selection

> Which Claude model to use, with which knobs, and how it maps onto the Token Leveragizer. The single
> source of truth for Anthropic model IDs across all WAVE spokes. Consumed not copied via `consume.sh`.
> Covers Claude **API** model choice + request surface + prompt caching. For Claude **Code** / MCP
> secrets wiring see [`frameworks/claude-config/`](../claude-config/) — different facet, do not duplicate.

## Principles

1. **Route, don't dial direct.** Every Claude call goes through the multi-tier router in
   [`frameworks/model-routing`](../model-routing/README.md) (local_30b → AI Gateway → OpenRouter →
   direct Anthropic → human). A direct `ANTHROPIC_API_KEY` call that skips the gateway loses
   observability + billing aggregation and is an anti-pattern.
2. **Never hardcode a model name in code.** The exact ID comes from routing config, not a string literal
   in a handler. This file tells the router *which* ID is current; code reads it from config.
3. **Exact-ID only, never a date suffix on an alias.** Use the bare alias (`claude-opus-4-8`). Appending
   a date (`claude-opus-4-8-20260205`) pins a snapshot that the API treats as a distinct, often-retired
   ID and is an anti-pattern. Aliases auto-resolve to the current snapshot.
4. **Never downgrade silently for cost.** Cost control is the router's job (tier 1 local first, budget
   caps). Swapping Opus→Haiku inside a frontier code path to save money, without a documented quality
   gate, is a silent regression. Escalate by policy, downgrade by eval.

## Which model when

| Model (exact ID) | Role | Pick it for |
|------------------|------|-------------|
| **`claude-opus-4-8`** | Most-capable; **default frontier/reasoning** | hard reasoning, agentic tool chains, production codegen, anything where a wrong answer is expensive |
| **`claude-sonnet-4-6`** | Balanced | high-volume drafting, summarization, mid-difficulty tool use, the gateway's default frontier fallback |
| **`claude-haiku-4-5`** | Fast / cheap | classification, routing, extraction, cheap first-draft, latency-critical surfaces |

Default to `claude-opus-4-8` when reasoning depth matters; only step down when an eval shows the cheaper
model clears the bar. The router already tries local 30B *before* any of these.

## Context / output limits

| Model | Context window | Max output tokens | Sampling params | Effort |
|-------|----------------|-------------------|-----------------|--------|
| `claude-opus-4-8` | 1M | 128K | **removed** (temperature/top_p/top_k → HTTP 400) | low/medium/high/max/**xhigh** (default high) |
| `claude-sonnet-4-6` | 1M | 64K | `temperature` still accepted | low/medium/high (default high) |
| `claude-haiku-4-5` | 200K | — | accepted | — |

## Stale IDs → migrate to

Any ID below is retired/legacy. Replace at the routing-config level; do not leave them in code.

| If you see… | Migrate to |
|-------------|------------|
| `claude-opus-4-7` / `4-6` / `4-5` / `4-1` / `4-0` | `claude-opus-4-8` |
| `claude-sonnet-4-5` / `4-0` / `3-x` | `claude-sonnet-4-6` |
| `claude-haiku-3-x` | `claude-haiku-4-5` |
| **any** date-suffixed opus/sonnet alias (e.g. `…-20260205`) | the bare alias above |

## Map onto the Token Leveragizer

The model IDs here populate the **frontier tiers** of `frameworks/model-routing`. The router still tries
the cheaper tiers first.

| Tier | Substrate | Claude role |
|------|-----------|-------------|
| 1. Local | Mac Studio 30B | — (no Claude; first attempt) |
| 2. AI Gateway | `VERCEL_AI_GATEWAY_API_KEY` | `claude-sonnet-4-6` default; `claude-opus-4-8` for declared reasoning calls |
| 3. OpenRouter | fallback | same IDs, redundant provider |
| 4. Direct Anthropic | `ANTHROPIC_API_KEY` | only when 2+3 down OR a feature is gateway-uncatalogued |
| 5. Human | Slack/PagerDuty | all model tiers failed |

The runnable shim ([`model-routing/local_offload`](../model-routing/), Anthropic frontend on `:8088`)
targets the hosted Anthropic API for its frontier endpoint — so Claude Code / Cursor connect unmodified
and still flow through the router.

## Thinking & effort (Opus 4.8 / 4.7)

- **Adaptive thinking ONLY**: `thinking={type:"adaptive"}`. The old
  `thinking={type:"enabled", budget_tokens:N}` returns **HTTP 400** — `budget_tokens` is fully removed on
  Opus 4.8/4.7.
- **Sampling params removed**: sending **any** of `temperature` / `top_p` / `top_k` returns **HTTP 400**
  on Opus 4.8/4.7. Steer via prompting + `effort` instead.
- **Effort** lives in `output_config.effort` = `low|medium|high|max` (+ `xhigh` on 4.7/4.8). Default
  `high`. `max` and `xhigh` are Opus-tier only.
- `thinking.display` defaults to `"omitted"` (reasoning text empty); set `"summarized"` to surface
  progress.
- **Sonnet 4.6**: adaptive thinking supported; `effort` supported (default `high`); `budget_tokens`
  deprecated; `temperature` still accepted (unlike Opus 4.8/4.7).

## Request surface

- **No last-assistant-turn prefill.** A trailing `assistant` message to prefill the reply returns **400**
  on Opus 4.8/4.7/4.6 and Sonnet 4.6. Use structured outputs (`output_config.format`) or a system
  instruction instead.
- **`output_config.format` is canonical.** The old top-level `output_format` param is deprecated.
- **Stream when `max_tokens` > ~16000** — non-streaming risks an SDK HTTP timeout. Consume with
  `.get_final_message()` (Python) / `.finalMessage()` (TS).
- **Handle every `stop_reason`**: `refusal` (read `stop_details.category`),
  `model_context_window_exceeded`, `pause_turn` (server tools — resume the turn), `max_tokens`.

## Prompt caching

Every spoke that calls Claude SHOULD cache its stable prefix. Mechanics:

- **Prefix match, order-sensitive.** Cache is a prefix match in render order `tools → system → messages`.
  Any byte change anywhere in the prefix invalidates everything after it. Keep stable content first;
  put volatile content (timestamps, uuids, per-request data) **after the last breakpoint**.
- **Breakpoints.** `cache_control {type:"ephemeral"}` = 5m TTL; `{type:"ephemeral", ttl:"1h"}` = 1h.
  Top-level `cache_control` on the request auto-caches the last cacheable block. **Max 4 breakpoints.**
- **Minimum cacheable prefix** (below this it silently won't cache — `cache_creation_input_tokens=0`):

  | Model | Min cacheable prefix |
  |-------|----------------------|
  | `claude-opus-4-8` | **1,024 tokens** |
  | `claude-sonnet-4-6` | 1,024 tokens |
  | `claude-haiku-4-5` | 4,096 tokens |

  > ⚠️ Nuance: an older cached skill table listed **4,096** as the opus-4-8 minimum. The live Anthropic
  > doc says **1,024** — that value is authoritative. Use 1,024 for opus/sonnet, 4,096 for haiku.

- **Pricing `claude-opus-4-8`**: `$5` / `$25` per MTok (input / output). 5m cache **write** = 1.25× base
  input; 1h write = 2× base input; cache **read** = 0.1× base input.
- **Verify it's hitting.** Read `usage.cache_read_input_tokens`. If it's `0` across identical-prefix
  requests, a silent invalidator is at work: `datetime.now()` in the system prompt, unsorted JSON in a
  tool schema, or a varying tool set. Sort + freeze the prefix.
- **Pre-warm** with a `max_tokens:0` request — it writes the cache and returns `content:[]`. Put the
  `cache_control` on the last **shared** block (system/tools), not on a throwaway user message.
- **Mid-conversation operator instructions**: append a `{role:"system", …}` entry to `messages[]`
  (beta `mid-conversation-system-2026-04-07`) instead of editing the top-level `system` — editing the
  top-level prefix invalidates the whole cache.

## Anti-patterns

- ❌ Hardcoding a model ID in code instead of reading it from routing config
- ❌ Date-suffixing an alias (`claude-opus-4-8-20260205`) — pins a retiring snapshot
- ❌ Leaving a retired ID (`claude-opus-4-6`, `claude-sonnet-4-5`, …) in config or code
- ❌ Silently downgrading Opus→Sonnet/Haiku in a frontier path for cost, with no eval gate
- ❌ Calling direct Anthropic without going through the gateway first (loses observability/billing)
- ❌ Sending `temperature`/`top_p`/`top_k` or `thinking.budget_tokens` to Opus 4.8/4.7 (→ HTTP 400)
- ❌ Last-assistant-turn prefill on 4.8/4.7/4.6/Sonnet-4.6 (→ 400); use `output_config.format`
- ❌ Non-streaming a `max_tokens > 16000` call (SDK timeout risk)
- ❌ A `datetime.now()`/uuid/unsorted-JSON in the cached prefix (silent cache miss)

## Env vars

| Var | Purpose |
|-----|---------|
| `VERCEL_AI_GATEWAY_API_KEY` | tier 2 — the path Claude calls SHOULD take |
| `ANTHROPIC_API_KEY` | tier 4 direct fallback only |
| `OLLAMA_API_KEY` | tier 1 (Mac Studio) — tried before any Claude tier |

## Related

- [`frameworks/model-routing/README.md`](../model-routing/README.md) — the multi-tier escalation this plugs into
- [`frameworks/model-routing/champions.md`](../model-routing/champions.md) — which models populate each tier
- [`frameworks/claude-config/`](../claude-config/) — Claude Code / MCP-secrets wiring via Doppler (sibling facet)
- [`frameworks/observability/README.md`](../observability/README.md) — capture `stop_reason:refusal` + cache-miss as ops signals
