# Claude API Migration Standard

> How every WAVE spoke targets the **current** Claude model generation and survives the breaking
> changes that landed with **Opus 4.8 / 4.7**. This is the *direct-API request-surface* standard —
> the model name and tier come from [`../model-routing`](../model-routing/README.md), not from code.
> For Claude **Code** / MCP-secrets wiring see the sibling [`../claude-config`](../claude-config/) (do
> not duplicate it here).

## Principles

1. **Never hardcode a model string in code.** It comes from routing config
   ([`../model-routing/champions.json`](../model-routing/champions.json)). This doc is the migration
   table that keeps that config — and any harvested call site — pointed at live models.
2. **Route through the gateway first.** Direct Anthropic is **tier 4**. Calling it without going
   through Vercel AI Gateway → OpenRouter loses observability + billing aggregation.
3. **Never append a date suffix to an alias.** `claude-opus-4-8` is the canonical string. A
   date-suffixed alias (`claude-opus-4-6-20260205`) is an anti-pattern — it pins a snapshot and rots.
4. **The frozen harvest is frozen.** Anything under `staging/_external/` is a verbatim third-party
   harvest — **do NOT migrate it.** Migrating it destroys the provenance fidelity it exists to record.

## Stale-ID → current model

Use these exact strings. Never add a date suffix to an alias.

| If code/config says… | Migrate to | Tier role |
|----------------------|-----------|-----------|
| `claude-opus-4-7`, `-4-6`, `-4-5`, `-4-1`, `-4-0` | **`claude-opus-4-8`** | most-capable; default frontier/reasoning. 1M ctx, 128K out |
| `claude-sonnet-4-5`, `-4-0`, `-3-*` (any 3.x) | **`claude-sonnet-4-6`** | balanced. 1M ctx, 64K out |
| `claude-haiku-3-*` (any 3.x) | **`claude-haiku-4-5`** | fast/cheap. 200K ctx |
| any `claude-opus-4-6-YYYYMMDD` (date-suffixed) | strip suffix → **`claude-opus-4-8`** | date-suffixed aliases are an anti-pattern |

## Breaking changes when targeting Opus 4.8 (and 4.7)

Opus 4.8/4.7 removed several request-surface params. Sending a removed param returns **HTTP 400** —
this is a hard break, not a deprecation warning. Migrate before flipping the model string.

| Old (4.6 and earlier) | New on Opus 4.8/4.7 | Failure if not migrated |
|-----------------------|---------------------|-------------------------|
| `temperature` / `top_p` / `top_k` | **removed** — steer via prompt + `effort` instead | **400** on ANY of them |
| `thinking={type:"enabled", budget_tokens:N}` | `thinking={type:"adaptive"}` | **400** — `budget_tokens` fully removed |
| (implicit verbosity) | `output_config.effort` = `low\|medium\|high\|max` (+ `xhigh`) | n/a (default `high`) |
| last-assistant-turn **prefill** | `output_config.format` (structured outputs) or a system instruction | **400** on Opus 4.8/4.7/4.6 + Sonnet 4.6 |
| top-level `output_format` | `output_config.format` | deprecated (still parsed; migrate) |
| non-streaming large response | **stream** when `max_tokens` > ~16000 | SDK HTTP timeout risk |

### Thinking & effort detail

- **Adaptive only on Opus 4.8/4.7.** `thinking={type:"adaptive"}`. The `enabled`+`budget_tokens` form
  is gone (400). `budget_tokens` does not map to anything — drop it, don't translate it.
- **`output_config.effort`** = `low|medium|high|max` (default `high`). `max` and `xhigh` are
  **Opus-tier only**; `xhigh` exists on 4.7/4.8. Use `effort` where you used to use `budget_tokens`
  to dial reasoning depth.
- **Reasoning text is hidden by default.** `thinking.display` defaults to `"omitted"` (reasoning text
  empty). Set `thinking.display:"summarized"` to surface progress in UI.
- **Sonnet 4.6** still **accepts `temperature`** (Opus 4.8/4.7 do not); supports adaptive thinking +
  `effort` (default `high`); `budget_tokens` deprecated there too.

### Stop-reason handling (all tiers)

Branch on `stop_reason` — do not assume `end_turn`:

| `stop_reason` | Action |
|---------------|--------|
| `refusal` | read `stop_details.category`; surface/route, don't retry blindly |
| `model_context_window_exceeded` | trim context / summarize, retry |
| `pause_turn` | server-tool pause — resume the turn |
| `max_tokens` | response truncated — raise cap or stream + continue |

### Streaming large outputs

When `max_tokens` > ~16000, **stream** (non-streaming risks SDK HTTP timeout). Collect with
`.get_final_message()` (Python) / `.finalMessage()` (TS).

## Prompt caching (REQUIRED for any repeated-prefix workload)

Per the live Anthropic prompt-caching doc:

- **Prefix match, byte-exact.** Any byte change *anywhere* in the prefix invalidates everything after
  it. Render order is **tools → system → messages**. Keep stable content first; put volatile content
  (timestamps, uuids, per-request data) **after the last breakpoint**.
- **Breakpoints:** `cache_control:{type:"ephemeral"}` (5m default) or `{type:"ephemeral",ttl:"1h"}`.
  A top-level `cache_control` on the request auto-caches the **last cacheable block**. Max **4**
  breakpoints.
- **Minimum cacheable prefix** (below it: silent no-cache, `cache_creation_input_tokens=0`):

  | Model | Min prefix tokens |
  |-------|-------------------|
  | `claude-opus-4-8` | **1,024** |
  | `claude-sonnet-4-6` | 1,024 |
  | `claude-haiku-4-5` | 4,096 |

  > ⚠️ **Nuance:** an older cached skill table listed **4,096** for Opus 4.8. The **1,024** value is
  > from the live caching doc and is authoritative — use 1,024 for 4.8.

- **Pricing (`claude-opus-4-8`):** $5 / $25 per MTok (input / output). 5m cache **write** = 1.25× base
  input; 1h write = 2× base input; cache **read** = 0.1× base input.
- **Verify hits:** check `usage.cache_read_input_tokens`. If it's `0` across identical-prefix
  requests, a silent invalidator is at work — `datetime.now()` in the system prompt, unsorted JSON, or
  a varying tool set ahead of the breakpoint.
- **Pre-warm:** a `max_tokens:0` request writes the cache and returns `content:[]`. Put the
  `cache_control` on the last **shared** block (system / tools), **not** on a placeholder user msg.
- **Mid-conversation operator instructions:** append `{role:"system", ...}` to `messages[]`
  (beta `mid-conversation-system-2026-04-07`) instead of editing the top-level `system` — editing
  top-level `system` busts the entire cached prefix.

## Migration checklist: [BLOCKS] vs [TUNE]

`[BLOCKS]` = will return HTTP 400 / break at runtime when you point at Opus 4.8 — fix before merge.
`[TUNE]` = works, but leaves quality / cost / hit-rate on the table — fix opportunistically.

- [BLOCKS] Any `temperature` / `top_p` / `top_k` on an Opus-4.8/4.7 call → remove; steer via prompt + `effort`.
- [BLOCKS] `thinking={type:"enabled", budget_tokens:N}` on Opus 4.8/4.7 → `thinking={type:"adaptive"}`.
- [BLOCKS] Last-assistant-turn **prefill** on Opus 4.8/4.7/4.6 or Sonnet 4.6 → `output_config.format` or system instruction.
- [BLOCKS] Stale model string (any row in the migration table) → current alias, no date suffix.
- [BLOCKS] `max_tokens` > ~16000 without streaming → stream + `.get_final_message()`/`.finalMessage()`.
- [TUNE] Top-level `output_format` → `output_config.format` (canonical).
- [TUNE] No `stop_reason` branch for `refusal` / `model_context_window_exceeded` / `pause_turn`.
- [TUNE] No prompt caching on a repeated-prefix workload, or `cache_read_input_tokens==0` (silent invalidator).
- [TUNE] Prefix below the model minimum (1,024 for 4.8/4.6; 4,096 for Haiku 4.5) → won't cache.
- [TUNE] Volatile content (timestamps/uuids) ahead of the last breakpoint → move it after.
- [TUNE] `thinking.display` left `"omitted"` where a UI should show progress → `"summarized"`.
- [TUNE] Editing top-level `system` mid-conversation → append `{role:"system"}` to `messages[]` instead.

## Anti-patterns

- ❌ Calling direct Anthropic without going through the gateway first (loses observability + billing).
- ❌ Hardcoding a model name in code instead of reading it from routing config.
- ❌ Appending a date suffix to an alias (`claude-opus-4-8-20260530`).
- ❌ Translating `budget_tokens` into a number on `adaptive` — it has no equivalent; drop it, use `effort`.
- ❌ Keeping `temperature` "just in case" on an Opus 4.8 call — it's a guaranteed 400.
- ❌ Putting `datetime.now()` / unsorted JSON / a varying tool set ahead of a cache breakpoint.
- ❌ **Migrating `staging/_external/`** — the harvest is frozen; rewriting model IDs there destroys fidelity.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only (gateway is the default path) |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 default path for Claude traffic (see `../model-routing`) |

> Model name is **not** an env var — it's resolved by routing config. Caching params, `effort`, and
> `thinking` live in the call config, not the environment.

## Related

- [`../model-routing/README.md`](../model-routing/README.md) — the 5-tier Token Leveragizer; **resolves which model + which tier**. This doc only covers the request surface once a Claude model is chosen.
- [`../model-routing/local_offload/`](../model-routing/local_offload/) — runnable chassis; its Anthropic shim on `:8088` targets the hosted Anthropic API as its frontier endpoint.
- [`../claude-config/`](../claude-config/) — Claude **Code** / MCP-secrets wiring via Doppler (different facet; may land separately).
- [`../observability/README.md`](../observability/README.md) — never forward an API key into Sentry/Linear `extra`.
