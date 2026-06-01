# Claude Prompt Caching Standard

> How every WAVE spoke caches a stable Claude prompt prefix to cut cost and latency — one pattern,
> consumed not copied. Caching is a property of the **request shape**, not a separate API: get the
> render order right and the savings are automatic and verifiable.

This file covers prompt caching only. Model selection / thinking / effort / request-surface rules live
in [`README.md`](./README.md); Claude **Code** + MCP-secret wiring (Doppler) is a different facet —
see [`frameworks/claude-config/`](../claude-config/), do not duplicate it here.

## The one invariant: prefix match

A cache entry is keyed by an **exact byte prefix** of the rendered request. Any byte change *anywhere*
in the prefix invalidates that breakpoint **and everything after it**. There is no fuzzy match.

Render order is fixed by the API: **`tools` → `system` → `messages`** (in array order). Cache from the
front:

```text
[ tools ][ system ][ messages... ]
  stable -------------------------> volatile
  ^------------- cache this --------^   ^-- per-request junk goes HERE (after the last breakpoint)
```

- Put **stable** content first: tool definitions, system policy, few-shot exemplars, large pinned docs.
- Put **volatile** content last: timestamps, request UUIDs, per-user state, the live user turn.
- A single moved/edited byte in `tools` busts the cache for the entire request. Treat the cached prefix
  as immutable per deploy.

## Breakpoints

Mark the end of a cacheable span with `cache_control` on a content block:

```jsonc
{ "type": "text", "text": "<stable system policy>",
  "cache_control": { "type": "ephemeral" } }            // 5m TTL (default)

{ "type": "text", "text": "<big pinned doc>",
  "cache_control": { "type": "ephemeral", "ttl": "1h" } } // 1h TTL
```

- **Max 4 breakpoints** per request. The API caches the longest matching prefix at each breakpoint and
  reuses whichever prefix matches on the next call.
- **Top-level auto-cache:** setting `cache_control` at the request top level auto-caches the **last
  cacheable block** without you hand-placing a breakpoint. Use this for the simple single-prefix case;
  use explicit breakpoints when you have nested stable/volatile spans (tools + system + a doc that
  changes at different cadences).
- Place breakpoints at **stable boundaries** — end of tools, end of system, end of the last pinned doc.
  Never put one mid-volatile.

## Minimum cacheable prefix

A prefix **shorter than the model minimum silently will not cache** — no error, just
`cache_creation_input_tokens = 0`.

| Model | Min cacheable prefix |
|-------|----------------------|
| `claude-opus-4-8` | **1,024 tokens** |
| `claude-sonnet-4-6` | 1,024 tokens |
| `claude-haiku-4-5` | 4,096 tokens |

> ⚠️ **Discrepancy flag:** an older cached skill table listed **4,096** as the `claude-opus-4-8`
> minimum. That is stale. The live Anthropic doc value is **1,024** for Opus 4.8 — authoritative here.
> If you see 4,096 quoted for Opus 4.8 anywhere downstream, it is wrong; this file is the source of truth.

## Pricing (claude-opus-4-8)

Base: **$5 / MTok input · $25 / MTok output**. Cache modifiers apply to the cached input tokens:

| Operation | Multiplier on base input | Effective ($/MTok) |
|-----------|--------------------------|--------------------|
| Cache **write**, 5m TTL | 1.25× | $6.25 |
| Cache **write**, 1h TTL | 2× | $10.00 |
| Cache **read** (hit) | 0.1× | $0.50 |

A hit is **10× cheaper** than re-sending the prefix. The 5m write pays for itself after ~1 reuse; the
1h write after ~2. Below the minimum prefix you pay full input price and cache nothing.

## Verify it actually cached

Read the `usage` block on every response:

| Field | Meaning |
|-------|---------|
| `cache_creation_input_tokens` | tokens written to cache this request (a write happened) |
| `cache_read_input_tokens` | tokens served **from** cache this request (a hit — the win) |
| `input_tokens` | uncached input billed at base rate |

Across identical-prefix requests, `cache_read_input_tokens` should be **> 0** from the second call on.
**If it stays 0, a silent invalidator is mutating the prefix.**

### Silent-invalidator audit table

| Symptom | Cause | Fix |
|---------|-------|-----|
| `cache_read = 0` on every call | `datetime.now()` / timestamp / request UUID inside `system` or tools | Move it into the last `messages` turn, after the last breakpoint |
| `cache_read = 0` intermittently | Unsorted JSON in a serialized tool result / system block (key order varies) | Serialize with sorted keys / canonical form |
| `cache_read = 0` after a deploy | Tool set reordered or a tool added/removed (changes the `tools` prefix) | Pin tool array order; gate tool changes behind a deploy, not per-request |
| `cache_creation = 0` AND `cache_read = 0` | Prefix below model minimum (see table) | Grow the stable prefix past the threshold, or don't bother caching it |
| Cache busts mid-conversation | Top-level `system` string edited to inject an operator note | Append a mid-conversation system message instead (below) |

## Pre-warm

To pay the write cost ahead of real traffic (deploy hook, scheduled warmer), send a `max_tokens: 0`
request. It writes the cache and returns `content: []` with no generation.

- Put `cache_control` on the **last shared block** (the system/tools prefix you want warm) —
  **not** on the throwaway user message. The placeholder user turn exists only to make a valid request;
  it must sit after the breakpoint so it isn't part of the cached prefix.
- Confirm the warm by checking `cache_creation_input_tokens > 0` on the warmer's response.

## 1h TTL — when to use

Default to **5m**. Reach for `ttl: "1h"` (2× write cost) only when:

- The prefix is large (tens of K tokens) **and** reused on a cadence slower than 5m but faster than 1h —
  e.g. a big pinned knowledge base hit a few times an hour.
- A long-running agent/session keeps the same system + tools across sparse turns.

If reuse is denser than every 5m, the 5m TTL already stays warm on each hit — don't pay 2× for 1h.

## Mid-conversation system messages

To inject an operator instruction *after* a conversation has started, **do not edit the top-level
`system`** — that mutates the cached prefix and busts every breakpoint after it. Instead append a system
message into `messages[]`:

```jsonc
{ "role": "system", "content": "Operator: switch to terse mode." }
```

Requires the `mid-conversation-system-2026-04-07` beta header. Because it lands at the end of `messages`
(after the last breakpoint), the cached `tools` + top-level `system` prefix stays intact and keeps hitting.

## WAVE note — caching on the gateway/chassis frontier

WAVE inference does **not** call Anthropic directly — it routes through the 5-tier Token Leveragizer
(`local_30b → Vercel AI Gateway → OpenRouter → direct Anthropic → human`), see
[`../model-routing/README.md`](../model-routing/README.md). Two consequences for caching:

- **Caching applies on the frontier passthrough.** When a call escalates to the Anthropic frontier (via
  the gateway, or via the `local_offload` Anthropic shim on `:8088` whose frontier endpoint targets the
  hosted Anthropic API), the `cache_control` blocks pass straight through. Build the request with the
  correct render order **at the call site** — the gateway/shim forwards it verbatim, it does not
  re-order or inject for you.
- **Don't hardcode the model.** The model id (`claude-opus-4-8` etc.) comes from routing config, never a
  string literal in spoke code (see model-routing Anti-patterns). The cache-prefix shape is independent
  of which model resolves — but the **minimum** is model-specific (table above), so a routing change
  from Opus→Haiku can drop you below threshold. Verify `cache_read_input_tokens` after any routing change.

## Anti-patterns

- ❌ Timestamp / UUID / `datetime.now()` anywhere in `tools` or `system` — guarantees `cache_read = 0`.
- ❌ Editing top-level `system` mid-conversation to add a note (use a `messages[]` system message).
- ❌ Putting the cache breakpoint on the throwaway user turn of a `max_tokens: 0` pre-warm.
- ❌ Reordering or conditionally including tools per request — pin the tool array, gate changes to deploys.
- ❌ Quoting 4,096 as the Opus 4.8 minimum (stale; it is 1,024).
- ❌ Assuming a cache hit — always confirm via `usage.cache_read_input_tokens`.
- ❌ Caching a prefix below the model minimum and expecting savings (silent no-cache).

## Env vars

Caching needs no env of its own; it rides the routing credentials.

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_API_KEY` | tier-4 direct frontier (caching passes through) |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 gateway (frontier passthrough preserves `cache_control`) |

## Enforcement (gate)

`lint-cache-control.sh` (gate id `claude-api-cache`, registered in `../gates/registry.yaml`) flags any
Claude request that sets a `system` prefix but never sets `cache_control` — run at commit time (pre-commit)
and in CI (`checks.yml`), inherited by every spoke via `foundation-gate.yml@v1`. Advisory during rollout.
A genuinely per-request-varying prefix that *shouldn't* cache is marked `cache-exempt` on the line. The
reference engine (`../model-routing/local_offload/shim/engine.py`) already caches the last `system` block
(or, if there's no system, the last tool) and accepts `req["cache_ttl"]=="1h"` for the 1-hour cache.

## Related

- [`README.md`](./README.md) — model strings, thinking/effort, request surface
- [`../model-routing/README.md`](../model-routing/README.md) — the 5-tier router caching rides on
- [`../claude-config/`](../claude-config/) — Claude Code / MCP-secret wiring (different facet)
- [`../observability/README.md`](../observability/README.md) — verify cache metrics flow to ops
