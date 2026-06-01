# Claude API Request Surface

> The canonical request shape for **direct** Anthropic Messages API calls inside WAVE — models, the
> thinking/effort surface, streaming, structured outputs, `stop_reason` handling, typed errors, and
> prompt caching. Direct calls are **tier 4** of the [Token Leveragizer](../model-routing/README.md):
> route through the gateway first. This file governs *how the bytes are shaped* when you do reach the
> wire. Claude **Code** / MCP-secrets wiring lives in [`frameworks/claude-config/`](../claude-config/)
> (different facet — cross-linked, not duplicated here).

## Models

Use the **alias** exactly as written. **NEVER** append a date suffix to an alias
(`claude-opus-4-8-20260205` is an anti-pattern — it pins a snapshot the routing layer can't manage).
Model strings come from [`model-routing`](../model-routing/champions.md) config — **do not hardcode**
one in code.

| Alias | Role | Context | Max output | Notes |
|-------|------|---------|-----------|-------|
| `claude-opus-4-8` | Default frontier / reasoning | 1M | 128K | most-capable; `max`+`xhigh` effort |
| `claude-sonnet-4-6` | Balanced | 1M | 64K | `temperature` still accepted |
| `claude-haiku-4-5` | Fast / cheap | 200K | — | |

**Migrate stale IDs:**

| Retired | → Replace with |
|---------|----------------|
| `claude-opus-4-7` / `4-6` / `4-5` / `4-1` / `4-0` | `claude-opus-4-8` |
| `claude-sonnet-4-5` / `4-0` / `3-x` | `claude-sonnet-4-6` |
| `claude-haiku-3-x` | `claude-haiku-4-5` |

## Thinking & effort (Opus 4.8 / 4.7)

- **Adaptive thinking ONLY:** `thinking={"type":"adaptive"}`. `{"type":"enabled","budget_tokens":N}`
  returns **HTTP 400** — `budget_tokens` is **fully removed** on Opus 4.8/4.7.
- **Sampling params removed:** `temperature` / `top_p` / `top_k` are **removed** on Opus 4.8/4.7.
  Sending *any* of them returns **HTTP 400**. Steer via prompting + effort instead.
- **Effort** lives in `output_config.effort = low|medium|high|max` (`xhigh` on 4.7/4.8). Default `high`.
  `max` and `xhigh` are **Opus-tier only**.
- `thinking.display` defaults to `"omitted"` (reasoning text empty). Set `"summarized"` to surface progress.
- **Sonnet 4.6:** adaptive thinking + effort supported (default `high`); `budget_tokens` deprecated;
  `temperature` still accepted (but Opus 4.8/4.7 rejects it).

## Request surface rules

- **No last-assistant-turn prefills.** A trailing `{"role":"assistant",...}` to force a prefix returns
  **400** on Opus 4.8/4.7/4.6 **and** Sonnet 4.6. Replace with **structured outputs**
  (`output_config.format`) or a `system` instruction.
- **`output_config.format` is canonical.** The old top-level `output_format` param is **deprecated** —
  do not use it.
- **Stream when `max_tokens` > ~16000.** A long non-streaming generation risks an SDK HTTP timeout.
  Use `.get_final_message()` (Python) / `.finalMessage()` (TS) to collect.

### Sensible `max_tokens` defaults

| Workload | `max_tokens` | Stream? |
|----------|-------------|---------|
| Classification / routing / short JSON | 1024 | no |
| Normal chat / tool turn | 4096 | no |
| Long synthesis / report / refactor | 16000 | **yes** |
| Opus full-length reasoning | up to 128K | **yes** |

`max_tokens` is the **cap**, not a target — it bounds cost and the timeout risk. Always set it
explicitly; never default to the model maximum.

## `stop_reason` handling

Branch on `response.stop_reason` every call — do not assume `end_turn`:

| `stop_reason` | Meaning | Action |
|---------------|---------|--------|
| `end_turn` | natural completion | use the content |
| `max_tokens` | hit the cap | raise cap or continue from the partial; warn if truncation matters |
| `refusal` | model declined | read `stop_details.category`; surface a clean message, don't retry blindly |
| `model_context_window_exceeded` | input + output overflowed the window | trim/compact input, then retry |
| `pause_turn` | a long-running **server tool** paused | echo the partial `content` back as the next turn's input to resume |
| `tool_use` | wants a tool | run it, append `tool_result`, loop |

```python
msg = resp  # a Message
if msg.stop_reason == "refusal":
    cat = msg.stop_details.category   # e.g. "policy"
    raise Refused(cat)
elif msg.stop_reason == "model_context_window_exceeded":
    inputs = compact(inputs); retry()
elif msg.stop_reason == "pause_turn":
    messages.append({"role": "assistant", "content": msg.content})  # resume
elif msg.stop_reason == "max_tokens":
    log.warning("output truncated at max_tokens")
```

## Typed exceptions

Catch the SDK's typed hierarchy — never a bare `except`:

| Exception | HTTP | Retry? |
|-----------|------|--------|
| `APIConnectionError` / `APITimeoutError` | — | yes, backoff |
| `RateLimitError` | 429 | yes, honor `retry-after` |
| `InternalServerError` | 5xx | yes, backoff |
| `BadRequestError` | 400 | **no** — it's a request-shape bug (prefill / `budget_tokens` / `temperature` on Opus) |
| `AuthenticationError` / `PermissionDeniedError` | 401 / 403 | no |
| `NotFoundError` | 404 | no (often a bad/retired model string) |

A sudden `BadRequestError` after a model bump almost always means a removed param
(`budget_tokens`, `temperature`/`top_p`/`top_k`) or a last-assistant prefill — see above.

## Reference call (Python)

```python
from anthropic import Anthropic, APIStatusError, RateLimitError

client = Anthropic()  # ANTHROPIC_API_KEY from env

def call(model, system, messages, max_tokens=4096, effort="high"):
    kwargs = dict(
        model=model,                       # from routing config, NOT hardcoded
        max_tokens=max_tokens,
        system=system,
        messages=messages,
        thinking={"type": "adaptive", "display": "summarized"},
        output_config={"effort": effort},  # low|medium|high|max(|xhigh on opus)
    )
    if max_tokens > 16000:                  # stream long generations
        with client.messages.stream(**kwargs) as s:
            final = s.get_final_message()
        return final
    return client.messages.create(**kwargs)
```

```python
# Structured output instead of a prefill:
output_config={"effort": "high", "format": {"type": "json_schema", "schema": MY_SCHEMA}}
```

## Reference call (curl)

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-opus-4-8",
    "max_tokens": 4096,
    "thinking": {"type": "adaptive", "display": "summarized"},
    "output_config": {"effort": "high"},
    "system": "You are a WAVE service agent.",
    "messages": [{"role": "user", "content": "Summarize the incident."}]
  }'
```

> Omit `temperature`/`top_p`/`top_k` and `budget_tokens` entirely on Opus 4.8/4.7 — their presence is a
> 400, not a no-op.

## Prompt caching

Caching is **expected** on any call with a stable, sizable prefix. Render order on the wire is
**`tools` → `system` → `messages`**, and prefix matching is **byte-exact**: any change anywhere in the
prefix invalidates **everything after it**.

- **Stable content first, volatile content last.** Timestamps, UUIDs, per-request IDs go **after the
  last breakpoint** — never inside the cached prefix.
- `cache_control: {"type":"ephemeral"}` → 5m TTL; `{"type":"ephemeral","ttl":"1h"}` → 1h. A top-level
  `cache_control` on the request auto-caches the last cacheable block. **Max 4 breakpoints.**
- **Minimum cacheable prefix:** `claude-opus-4-8` = **1,024 tokens**, `claude-sonnet-4-6` = 1,024,
  `claude-haiku-4-5` = 4,096. Below the minimum it **silently won't cache**
  (`cache_creation_input_tokens` stays 0). *(Nuance: an older cached skill table listed 4,096 for 4.8;
  the live Anthropic doc value of **1,024** is authoritative — use 1,024.)*
- **Verify:** check `usage.cache_read_input_tokens`. If it's `0` across identical-prefix requests, a
  silent invalidator is at work — `datetime.now()` in the system prompt, unsorted JSON, or a varying
  tool set reordering the prefix.
- **Pre-warm:** a `max_tokens: 0` request writes the cache and returns `content: []`. Put the
  `cache_control` on the last **shared** block (`system`/`tools`), not on the placeholder user message.
- **Mid-conversation operator instructions:** append `{"role":"system",...}` to `messages[]`
  (beta `mid-conversation-system-2026-04-07`) instead of editing the top-level `system` — this preserves
  the cached prefix.

### Pricing (`claude-opus-4-8`, per MTok)

| Item | Rate |
|------|------|
| Input | $5 |
| Output | $25 |
| 5m cache write | 1.25× base input |
| 1h cache write | 2× base input |
| Cache read | 0.1× base input |

## Anti-patterns

- ❌ Calling direct Anthropic without going through the [gateway](../model-routing/README.md) first
  (loses observability + billing aggregation).
- ❌ Hardcoding a model string in code instead of reading [routing config](../model-routing/champions.md).
- ❌ Appending a date suffix to an alias (`claude-opus-4-8-20260205`).
- ❌ Sending `temperature`/`top_p`/`top_k` or `thinking.budget_tokens` to Opus 4.8/4.7 → 400.
- ❌ A trailing `assistant` prefill turn to force a prefix → 400. Use `output_config.format`.
- ❌ Top-level `output_format` (deprecated) instead of `output_config.format`.
- ❌ Non-streaming a `max_tokens > 16000` generation (SDK timeout risk).
- ❌ Volatile content (`datetime.now()`, UUIDs) inside the cached prefix → silent cache misses.
- ❌ Assuming `stop_reason == "end_turn"`; ignoring `refusal` / `pause_turn` /
  `model_context_window_exceeded`.
- ❌ Bare `except` around an SDK call instead of the typed hierarchy.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only (see [model-routing](../model-routing/README.md)) |
| `VERCEL_AI_GATEWAY_API_KEY` | tier 2 — the path you should normally take |

## Related

- [`model-routing/README.md`](../model-routing/README.md) — the 5-tier Token Leveragizer (direct API = tier 4)
- [`model-routing/champions.md`](../model-routing/champions.md) — the model-string source of truth
- [`model-routing/local_offload/`](../model-routing/local_offload/) — runnable Anthropic shim on `:8088`; its frontier endpoint targets the hosted Anthropic API
- [`claude-config/`](../claude-config/) — Claude Code / MCP-secrets wiring via Doppler (different facet)
- [`observability/README.md`](../observability/README.md) — wrap failure paths with `notifyOps`
