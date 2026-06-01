# Claude Long-Run Context Standard

> How every WAVE spoke keeps a long-running Claude conversation inside the window — compaction,
> context-editing, window sizing, token-counting, and the operator channel — one pattern, consumed
> not copied. Context is a finite resource with diminishing returns (*context rot*): curating what
> Claude sees matters as much as how much fits.

This file covers long-run context only. Caching mechanics live in [`prompt-caching.md`](./prompt-caching.md);
model/thinking/effort/request-surface rules live in [`README.md`](./README.md) and
[`thinking-and-effort.md`](./thinking-and-effort.md). Routing — never bypass the gateway — is the
[model-routing Leveragizer](../model-routing/README.md). Do not hardcode a model name anywhere; the
strings below are the live aliases, not call-site constants.

## Five mechanisms, when to reach for which

| Mechanism | Beta header | What it does | Reach for when |
|-----------|-------------|--------------|----------------|
| **Compaction** | `compact-2026-01-12` | Server summarizes old turns into a `compaction` block near the window limit | **Default** for long chats + multi-turn agentic tasks. Recommended primary strategy. |
| **Context editing** | `context-management-2025-06-27` | Prunes stale tool results / thinking blocks before the prompt reaches Claude | Fine-grained control: heavy tool-use, or thinking-block cache tuning |
| **Context windows** | — | 1M (opus/sonnet) vs 200k (haiku); overflow stop reason | Sizing budgets, picking a model, handling overflow |
| **Token counting** | — | `count_tokens` estimate before send (free, rate-limited) | Cost/rate planning + routing decisions |
| **Mid-conversation system** | — (opus-4-8 only) | Append `role:system` to `messages[]` without busting cache | Inject authoritative instruction mid-session |

Models with a 1M window + compaction support: `claude-opus-4-8` (default), `claude-opus-4-7`,
`claude-opus-4-6`, `claude-sonnet-4-6`. `claude-haiku-4-5` = 200k window, no compaction.

## Compaction (primary strategy)

Enable via `context_management.edits` with the beta header. The API detects the trigger threshold,
emits a `compaction` block summarizing prior turns, and continues. On every subsequent request the API
**drops all blocks before the last `compaction` block**.

```python
resp = client.beta.messages.create(
    betas=["compact-2026-01-12"],
    model="claude-opus-4-8",              # alias from routing config — never a literal here
    max_tokens=4096,
    messages=messages,
    context_management={"edits": [{
        "type": "compact_20260112",
        "trigger": {"type": "input_tokens", "value": 150000},  # default 150k; min 50k
    }]},
)
# CRITICAL: append the whole content array (carries the compaction block), not response.text.
messages.append({"role": "assistant", "content": resp.content})
```

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: compact-2026-01-12" -H "content-type: application/json" \
  -d '{"model":"claude-opus-4-8","max_tokens":4096,
       "messages":[{"role":"user","content":"Help me build a website"}],
       "context_management":{"edits":[{"type":"compact_20260112"}]}}'
```

The `compaction` block arrives first in `content`; `text` follows. Pass it back to continue with the
shortened prompt — the API ignores everything before it, so you may keep full history or drop it
yourself.

| Param | Default | Notes |
|-------|---------|-------|
| `trigger` | 150,000 input tokens | `{type:input_tokens, value:N}`; **min 50k** |
| `pause_after_compaction` | `false` | Returns `stop_reason:"compaction"` after the summary so you can inject blocks (preserve recent turns, wrap-up notes) before continuing |
| `instructions` | `null` | **Completely replaces** the default summary prompt — does not supplement it |

**Total-budget pattern**: set `pause_after_compaction:true`, count `stop_reason=="compaction"` events,
and once `n_compactions * trigger >= TOTAL_TOKEN_BUDGET` append a user turn asking Claude to wrap up.

**Streaming**: a `compaction` block emits one `content_block_start`, a single `content_block_delta`
(`compaction_delta`, full summary — no incremental streaming), then `content_block_stop`.

## Context editing (fine-grained)

Two server-side strategies, header `context-management-2025-06-27`. Applied **server-side before** the
prompt reaches Claude — keep your full unmodified history client-side; do **not** sync to the edited
version.

**Tool result clearing** (`clear_tool_uses_20250919`) — clears oldest tool results first, leaving a
placeholder so Claude knows. `clear_tool_inputs:true` also drops the tool call params.

**Thinking block clearing** (`clear_thinking_20251015`) — `keep:{type:thinking_turns, value:N}` or
`keep:"all"`. **Default varies by model — set `keep` explicitly if you route across tiers.** Opus 4.5+
and Sonnet 4.6+ keep all prior thinking by default; earlier Opus/Sonnet + all Haiku keep last turn only.

```python
context_management={"edits": [
    {"type": "clear_thinking_20251015", "keep": "all"},   # MUST be listed first
    {"type": "clear_tool_uses_20250919",
     "trigger": {"type": "input_tokens", "value": 30000},   # default 100k
     "keep": {"type": "tool_uses", "value": 3},             # default 3 pairs
     "clear_at_least": {"type": "input_tokens", "value": 5000},
     "exclude_tools": ["web_search"]},
]}
```

| Tool-clearing option | Default | Notes |
|----------------------|---------|-------|
| `trigger` | 100,000 input tokens | `input_tokens` or `tool_uses` |
| `keep` | 3 tool uses | recent pairs preserved |
| `clear_at_least` | none | min tokens cleared; if unmet the edit is skipped (cache-worthiness gate) |
| `exclude_tools` | none | tool names never cleared |

**Cache interaction** (this is the load-bearing nuance):
- Tool-result clearing **invalidates** the cached prefix at the clear point. Use `clear_at_least` so
  the saved tokens justify the cache write. You pay one write, then reuse the new prefix.
- Thinking-block clearing: **kept** → cache preserved (hits continue); **cleared** → cache invalidated
  at the clear point. Tune `keep` for cache-performance vs window-availability.

Inspect what ran via the `context_management.applied_edits` response field
(`cleared_input_tokens`, `cleared_tool_uses`, `cleared_thinking_turns`); for streaming it lands in the
final `message_delta`.

## Context windows + overflow

- **1M tokens**: `claude-opus-4-8` / `-4-7` / `-4-6`, `claude-sonnet-4-6` (Claude API, Bedrock, Vertex).
  Microsoft Foundry caps opus-4-8 at **200k**. `claude-haiku-4-5` = 200k.
- Up to 600 images/PDF pages per request (100 on 200k-window models); watch request-size limits.
- **Thinking is stripped automatically** from prior turns — `context_window = (input - prior_thinking)
  + current_turn`. The one exception: a thinking block **must** be returned alongside its
  corresponding `tool_result` (signature-verified; modifying it errors).
- **Context awareness** (Sonnet 4.6/4.5, Haiku 4.5 — *not* Opus): the model receives
  `<budget:token_budget>` + per-tool-call `<system_warning>` remaining-token updates. Lean on it for
  long agent sessions on those models.
- **Overflow** (4.5+): request is accepted; if generation hits the limit it stops with
  `stop_reason:"model_context_window_exceeded"`. Handle that stop reason; do not assume a 400.

## Token counting (cost / rate / routing planning)

Free, but rate-limited per usage tier (T1 100 RPM → T4 8,000 RPM) and **independent** of message
creation limits. Returns an **estimate** — actual may differ slightly; you are not billed for
system-added tokens.

```python
n = client.messages.count_tokens(
    model="claude-opus-4-8", system="…", messages=messages, tools=tools,
).input_tokens
# Route on this: if n + max_tokens approaches the window, escalate tier or compact.
```

Pass `context_management` + the beta header to `count_tokens` to **preview post-edit** size:
`context_management.original_input_tokens - input_tokens` = tokens saved. This is the WAVE pre-flight
gate — feed `input_tokens` into the [Leveragizer](../model-routing/README.md) budget caps before any
billable call. Token counting does **not** use caching (passing `cache_control` is a no-op here).

## Mid-conversation system messages (operator channel)

Opus-4-8 only, **no beta header**. Append a `{"role":"system"}` entry to `messages[]` to add an
authoritative instruction mid-session **without** editing the top-level `system` field — which would
re-hash the prefix and bust the cache for everything after it.

```python
messages = [
    {"role": "user", "content": "Review process() for perf."},
    {"role": "assistant", "content": "Use a generator for large inputs."},
    {"role": "user", "content": "Now review the calling code."},
    # Cache-preserving: earlier turns stay byte-identical, so the cached prefix still hits.
    {"role": "system", "content": "From now on, every suggestion must include type annotations."},
]
resp = client.messages.create(
    model="claude-opus-4-8", max_tokens=1024,
    cache_control={"type": "ephemeral"},     # caching is opt-in; without it nothing is saved
    system="You are a code review assistant. Be concise.",
    messages=messages,
)
```

Rules: later system messages outrank earlier ones and outrank top-level `system` for following turns.
A system message **cannot be first**, must immediately follow a `user` turn (or an `assistant` turn
ending in server tool use), and must be last or be followed by an `assistant` turn — else 400.
Consecutive system messages are disallowed (merge or wait for the next user turn). Append; never edit a
sent one. **Not a security boundary** — it grants priority, not trust; sanitize third-party content.

## ZDR + batch posture

- Compaction, context-editing, context-windows, token-counting, mid-conversation-system, and prompt
  caching are **all ZDR-eligible**.
- The **Batch API is 50% off but NOT ZDR-eligible** — never route ZDR-tenant context through batch.
- Stream whenever `max_tokens > 16000`.

## Anti-patterns

- ❌ Appending `response.content[0].text` instead of the full `response.content` after compaction —
  drops the `compaction` block and the next request re-sends (or errors on) the whole history.
- ❌ Editing the top-level `system` field mid-session when you mean to add an instruction — bust the
  cache. Use a mid-conversation system message (opus-4-8) instead.
- ❌ Relying on the per-model `clear_thinking` / Opus-vs-Sonnet defaults while routing across tiers —
  set `keep` explicitly.
- ❌ Tool-result clearing without `clear_at_least` — small clears bust the cache for no net win.
- ❌ Treating `count_tokens` as exact / billable, or as a cache primitive.
- ❌ Date-suffixing a model alias (e.g. `claude-opus-4-8-20260…`) or hardcoding it at the call site —
  read it from the routing config; never bypass the gateway for direct Anthropic.
- ❌ Sending ZDR-tenant conversations through the Batch API.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only — prefer the gateway (see model-routing) |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 gateway; carries usage/billing aggregation for token budgets |
| `WAVE_COMPACT_TRIGGER` | per-spoke compaction `trigger.value` override (≥ 50000) |
| `WAVE_CONTEXT_TOKEN_BUDGET` | total-token-budget ceiling for the pause-after-compaction loop |

Sources: build-with-claude/compaction.md, build-with-claude/context-editing.md, build-with-claude/context-windows.md, build-with-claude/token-counting.md, build-with-claude/mid-conversation-system-messages.md
