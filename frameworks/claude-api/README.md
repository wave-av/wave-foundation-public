# Claude API Standard

> How every WAVE spoke calls the Anthropic Claude API correctly — model selection, thinking/effort,
> request surface, and prompt caching — for the **current** model generation (Opus 4.8 / Sonnet 4.6 /
> Haiku 4.5). Consumed read-only via `consume.sh`; this is the floor every AI call site meets.

This standard is **the API contract**, not the routing decision. *Which* tier a call lands on and
*which* model populates it is owned by [`frameworks/model-routing`](../model-routing/README.md) (the
5-tier Token Leveragizer). *How* Claude CODE / MCP / secrets are wired is owned by
`frameworks/claude-config/` (Doppler — sibling, may land separately). This file owns *how the HTTP
request to Anthropic is shaped* once routing has decided to make one.

## Default model

**`claude-opus-4-8`** is the default frontier/reasoning model: 1M context, 128K max output, adaptive
thinking, effort up to `xhigh`. Never call it directly — it is the tier-4 substrate behind the gateway
(see "Composition" below). Never hardcode it; the alias comes from routing config.

| Model | Context | Max output | Role | Thinking | Effort ceiling | Temp/top_p/top_k |
|-------|---------|-----------|------|----------|----------------|------------------|
| `claude-opus-4-8` | 1M | 128K | default frontier / reasoning | adaptive only | `xhigh` | **removed (400)** |
| `claude-sonnet-4-6` | 1M | 64K | balanced workhorse | adaptive | `high` | temperature accepted |
| `claude-haiku-4-5` | 200K | — | fast / cheap | — | `high` | accepted |

> **Aliases only — NEVER append a date suffix.** `claude-opus-4-6-20260205` is an anti-pattern. Use the
> bare alias and let the platform resolve the snapshot.

### Stale IDs → migrate to

| You may find | Replace with |
|--------------|--------------|
| `claude-opus-4-7` / `-4-6` / `-4-5` / `-4-1` / `-4-0` | `claude-opus-4-8` |
| `claude-sonnet-4-5` / `-4-0` / `-3-*` | `claude-sonnet-4-6` |
| `claude-haiku-3-*` | `claude-haiku-4-5` |
| any date-suffixed opus/sonnet alias | the bare alias |

## Composition (where this sits)

```text
frameworks/model-routing   →  picks the tier + the model alias (Leveragizer)
frameworks/claude-api      →  shapes the Anthropic request (THIS file)
frameworks/claude-config   →  Claude Code / MCP / Doppler secrets (sibling facet)
```

- All inference routes through the [Leveragizer](../model-routing/README.md):
  `local_30b (Studio) → Vercel AI Gateway → OpenRouter → direct Anthropic → human`. **Never** call
  direct Anthropic without going through the gateway first — you lose observability + billing aggregation.
- The runnable chassis is [`model-routing/local_offload`](../model-routing/local_offload/) — an
  Anthropic-shaped shim on `:8088` whose frontier endpoint targets the hosted Anthropic API. Point your
  SDK `base_url` at the shim, not at `api.anthropic.com`.
- The rules below (model IDs, thinking, caching) apply equally whether the request egresses via the
  gateway, the shim, or — only when both are down — the direct fallback.

## Thinking & effort (Opus 4.8 / 4.7)

- **Adaptive thinking ONLY**: `thinking={type:"adaptive"}`. `{type:"enabled", budget_tokens:N}` returns
  **HTTP 400** — `budget_tokens` is fully removed on Opus 4.8/4.7.
- **Sampling params are removed**: sending *any* of `temperature` / `top_p` / `top_k` on Opus 4.8/4.7
  returns **HTTP 400**. Steer via prompting + `effort` instead.
- **`effort`** lives in `output_config.effort` = `low | medium | high | max` (plus `xhigh` on 4.7/4.8).
  Default `high`. `max` and `xhigh` are Opus-tier only.
- `thinking.display` defaults to `"omitted"` (reasoning text empty). Set `"summarized"` to surface
  progress to operators/UI.
- **Sonnet 4.6**: adaptive thinking supported; `effort` supported (default `high`); `budget_tokens`
  deprecated; `temperature` **still accepted** (unlike Opus 4.8/4.7).

## Request surface

- **No last-assistant-turn prefills.** A trailing `assistant` message returns **400** on Opus 4.8/4.7/4.6
  and Sonnet 4.6. Replace with a structured output (`output_config.format`) or a system instruction.
- **`output_config.format` is canonical.** The old top-level `output_format` param is deprecated.
- **Stream when `max_tokens > ~16000`** — non-streaming risks an SDK HTTP timeout. Collect with
  `.get_final_message()` / `.finalMessage()`.
- **Handle `stop_reason`**: `refusal` (read `stop_details.category`), `model_context_window_exceeded`,
  `pause_turn` (server tools), `max_tokens`. Don't assume `end_turn`.

## Prompt caching

Caching is **required** for any repeated-prefix call site (system prompts, tool defs, long docs). The
prefix is matched **byte-for-byte**: any change *anywhere* in the prefix invalidates *everything after
it*. Render order is **tools → system → messages**.

- **Stable content first; volatile content (timestamps, UUIDs, per-request data) AFTER the last
  breakpoint.** A `datetime.now()` in the system prompt silently kills the whole cache.
- `cache_control {type:"ephemeral"}` = 5m (default); `{type:"ephemeral", ttl:"1h"}` = 1h. Top-level
  `cache_control` on the request auto-caches the last cacheable block. **Max 4 breakpoints.**
- **Minimum cacheable prefix** (below it, silent no-cache → `cache_creation_input_tokens=0`):

  | Model | Min prefix |
  |-------|-----------|
  | `claude-opus-4-8` | **1,024 tokens** |
  | `claude-sonnet-4-6` | 1,024 tokens |
  | `claude-haiku-4-5` | 4,096 tokens |

  > **Nuance flagged:** an older cached skill table listed 4,096 for Opus 4.8. The **1,024** value above
  > is from the live official caching doc and is authoritative — use 1,024.

- **Pricing (opus-4-8)**: `$5 / $25` per MTok (input / output). 5m cache write = `1.25×` base input;
  1h write = `2×`; cache read = `0.1×`.
- **Verify** with `usage.cache_read_input_tokens`. If it is `0` across identical-prefix requests, a
  silent invalidator is at work — `datetime.now()` in the system prompt, unsorted JSON, or a varying
  tool set between calls.
- **Pre-warm** with a `max_tokens:0` request: it writes the cache and returns `content:[]`. Put the
  `cache_control` on the last SHARED block (system/tools), **not** on the placeholder user message.
- **Mid-conversation operator instructions**: append a `{role:"system", ...}` entry to `messages[]`
  (beta `mid-conversation-system-2026-04-07`) instead of editing the top-level `system` — editing
  top-level `system` invalidates the cached prefix.

## What good looks like

> Default `claude-opus-4-8` (bare alias, no date) reached via the gateway · adaptive thinking, no
> `budget_tokens`/`temperature` · structured outputs not prefills · streaming over 16K · `stop_reason`
> handled · stable prefix cached with a verified non-zero `cache_read_input_tokens`.

## Anti-patterns

- ❌ Hardcoding a model name in code instead of taking it from routing config.
- ❌ Date-suffixing an alias (`claude-opus-4-8-20260...`).
- ❌ Sending `temperature` / `top_p` / `top_k` or `thinking.budget_tokens` to Opus 4.8/4.7 (→ 400).
- ❌ Last-turn `assistant` prefill (→ 400); use `output_config.format`.
- ❌ Calling `api.anthropic.com` directly, bypassing the gateway/shim (loses observability + billing).
- ❌ Putting a timestamp/UUID/unsorted-JSON in the cached prefix (silent cache miss).
- ❌ Non-streaming requests with `max_tokens > 16000` (SDK timeout risk).
- ❌ Editing top-level `system` mid-conversation instead of appending a `system` message.

## Enforcement (left-shift gate)

This standard is executable, not just advisory. `lint-request-shape.sh` is the gate form of
`model-matrix.md` — it blocks the forbidden shapes above (temperature/top_p/top_k on Opus 4.x,
date-suffixed model IDs, `budget_tokens` on Opus 4.7/4.8, `effort` on Haiku 4.5, deprecated
`output_format`) so they're caught **as code is written**, not as a 400 in production:

- **Locally** — wired as a `pre-commit` hook (foundation's `.pre-commit-config.yaml`; spokes point it
  at the vendored `.foundation/frameworks/claude-api/lint-request-shape.sh`).
- **In CI, everywhere** — the reusable `checks.yml` (inherited by every spoke via `foundation-gate.yml`)
  runs the **same vendored script** — single source of truth, no drift. Advisory on rollout; hardens to
  blocking after soak. Foundation runs it blocking against itself (`self-check.yml`).
- **New spokes** are born with both hooks via the scaffolder's `.pre-commit-config.yaml` template.

Escape a deliberate case with `claude-api-lint: ignore` on the line, or `claude-api-lint: skip` for a
whole file (e.g. the reference shim that handles these params by design). Scans code files only —
never `.md`, so this doc's own ❌ examples don't trip it; honors the `staging/` FIDELITY rule.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only — gateway/shim is the default path |
| `ANTHROPIC_BASE_URL` | point the SDK at the `local_offload` shim (`:8088`) or the gateway |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 egress (see model-routing) |

## Related

- [`frameworks/model-routing/README.md`](../model-routing/README.md) — the 5-tier Leveragizer; owns model selection + escalation.
- [`frameworks/model-routing/local_offload/`](../model-routing/local_offload/) — runnable Anthropic-shaped shim (`:8088`).
- `frameworks/claude-config/` — Claude Code / MCP / Doppler secrets (sibling facet; cross-link, do not duplicate).
- [`frameworks/observability/README.md`](../observability/README.md) — wrap inference failures in `notifyOps`.
