# Model Matrix

> Per-model **capability + constraints** for the Claude API, with the **do-this-instead** for every
> constraint. This is the heart of *"every model has different requirements"*: a knob that is a no-op
> on one model is a **hard HTTP 400** on another. Route by capability, never by habit.
>
> **Default model: `claude-opus-4-8`** (frontier reasoning). `claude-sonnet-4-6` = balanced;
> `claude-haiku-4-5` = fast/cheap. Always pass the exact alias string — **never date-suffix an alias**
> and **never hardcode a model in code** (route via the [model-routing](../model-routing/README.md)
> Leveragizer: `local → gateway → openrouter → direct → human`).

## The matrix

| Capability / Constraint | `claude-opus-4-8` (default) | `claude-opus-4-7` | `claude-sonnet-4-6` | `claude-haiku-4-5` |
|---|---|---|---|---|
| **Role** | frontier / reasoning | prev frontier | balanced | fast / cheap |
| **Context window** | 1M | 1M | 1M | 200K |
| **Max output** | 128K | 128K | 64K | see model-comparison |
| **Thinking mode** | **adaptive only** | **adaptive only** | adaptive (+ deprecated manual) | adaptive |
| **`thinking.budget_tokens`** | ❌ **400** | ❌ **400** | accepted but **deprecated** | accepted |
| **`temperature`/`top_p`/`top_k`** | ❌ **400** | ❌ **400** | accepted | accepted |
| **`output_config.effort`** | low/med/high/**xhigh**/**max** | low/med/high/**xhigh**/**max** | low/med/high/**max** | ❌ **not supported** |
| **Effort default** | `high` | `high` | `high` | n/a |
| **`thinking.display` default** | `omitted` | `omitted` | `summarized` | `summarized` |
| **Last-assistant prefill** | ❌ **400** | ❌ **400** | ❌ **400** | accepted |
| **Min cacheable prefix** | **1,024** (see nuance) | 4,096 | 1,024 | 4,096 |
| **Structured outputs** | ✅ GA | ✅ GA | ✅ GA | ✅ GA |
| **Prior-thinking retention** | all turns kept | all turns kept | all turns kept | last turn only |

### Legacy note

Models **before** the 4.6/4.7/4.8 line (Opus 4.6/4.5, Sonnet 4.5/4, all Haiku ≤4.5) do **not**
support adaptive thinking — they require **manual** `thinking:{type:"enabled", budget_tokens:N}` and
**reject** `thinking:{type:"adaptive"}`. Opus 4.6 / Sonnet 4.6 accept *both* (manual is deprecated).
`effort` is supported on Opus 4.5/4.6 + Sonnet 4.6 but **not** on any Haiku. Treat anything older as a
distinct routing class — see [model-selection.md](./model-selection.md) for the retired-model map.

---

## Constraint → solution

### Thinking mode (adaptive vs manual)

Opus 4.8 / 4.7 support **adaptive thinking only**. Thinking is **off** unless you explicitly send
`thinking:{type:"adaptive"}`; manual `{type:"enabled", budget_tokens:N}` is **rejected with 400**.

- ❌ `thinking={"type":"enabled","budget_tokens":20000}` on Opus 4.8/4.7 → **400**.
- ✅ `thinking={"type":"adaptive"}` + control depth with `output_config.effort`.
- `max_tokens` remains the **hard** cap on total output (thinking + text); `effort` is **soft** guidance.

```python
# Opus 4.8: enable thinking + steer depth with effort (NOT budget_tokens)
resp = client.messages.create(
    model=route.model,                       # never a literal — route it
    max_tokens=32000,
    thinking={"type": "adaptive"},           # 400 if {"type":"enabled", budget_tokens:N}
    output_config={"effort": "xhigh"},       # low|medium|high|xhigh|max
)
```

On Sonnet 4.6, manual `budget_tokens` still *works* but is deprecated — migrate to adaptive + effort.

### Sampling params (`temperature` / `top_p` / `top_k`)

**Removed** on Opus 4.8/4.7 — sending **any** of them is **400**, not a silent no-op. Still accepted on
Sonnet 4.6 and Haiku 4.5.

- ❌ Migrating `temperature=0` (old "determinism" pattern) onto Opus 4.8/4.7 → **400**.
- ✅ **Delete** the param. Steer with prompting + `effort`; pin output shape with
  `output_config.format` (structured outputs) when you need a deterministic *schema*.

```python
# WRONG on Opus 4.8/4.7 → 400
# client.messages.create(model="claude-opus-4-8", temperature=0, top_p=0.9, ...)

# RIGHT — omit sampling entirely; use a schema for shape determinism
client.messages.create(
    model=route.model, max_tokens=4096,
    output_config={"format": {"type": "json_schema", "schema": SCHEMA}},
)
```

### Effort (`output_config.effort`)

`low | medium | high | xhigh | max`. Default `high` (omitting == `high`). **`xhigh` and `max` are
Opus-only** (Opus 4.8/4.7). **`effort` is not supported on `claude-haiku-4-5`** — Haiku is absent from
the effort supported-models list; sending `effort` to Haiku is a request-shape error.

- ❌ `output_config={"effort":"xhigh"}` on Sonnet 4.6 (max is fine, xhigh is Opus-only).
- ❌ Any `effort` on Haiku 4.5 → **drop it** and route the cheap path without the knob.
- ✅ Opus coding/agentic: start at **`xhigh`** with a large `max_tokens` (≥64K). Sonnet default
  workflow: **`medium`**. Latency-critical Sonnet: **`low`**.

```python
def effort_for(model: str, want: str) -> dict:
    if model.startswith("claude-haiku"):
        return {}                            # Haiku: effort unsupported — omit
    if want in ("xhigh",) and not model.startswith("claude-opus"):
        want = "max" if want == "xhigh" else want   # xhigh is Opus-only
    return {"effort": want}
```

### `thinking.display` (silent default change)

Opus 4.8/4.7 default `display` to **`"omitted"`** (empty `thinking` field, signature still carried);
Sonnet 4.6 / Opus 4.6 default to `"summarized"`. This is a **silent** change from 4.6 — code that read
`block.thinking` to log reasoning will suddenly see empty strings on Opus 4.8.

- ✅ To surface reasoning, set `thinking={"type":"adaptive","display":"summarized"}` explicitly.
- ✅ Keep `"omitted"` (the default) for server-to-server — it streams the final text **sooner** (lower
  TTFT) and costs the same (you're billed for full thinking tokens either way).
- `display` is invalid with `thinking.type:"disabled"`.

### Last-assistant-turn prefill

A trailing `{"role":"assistant", ...}` to *force* the start of the response returns **400** on Opus
4.8/4.7/**4.6** **and** Sonnet 4.6. (Still accepted on Haiku 4.5.)

- ❌ `messages=[..., {"role":"assistant","content":"{"}]` to force JSON → **400** on the 4.6+ line.
- ✅ Replace with **structured outputs** (`output_config.format`) for shape, or a `system` instruction
  for tone/voice. `output_config.format` is **canonical** — the top-level `output_format` param is
  **deprecated** (still works for a transition period; do not write new code against it).

### Prompt caching + min cacheable prefix

Prefix-match caching; mark a block with `cache_control:{type:"ephemeral"}`, or set one **top-level**
`cache_control` for **automatic** caching (breakpoint auto-advances). **Max 4 breakpoints**;
automatic-cache consumes one slot (400 if all 4 explicit slots are taken). 5-min TTL by default;
add `"ttl":"1h"` for the 1-hour cache.

**Min cacheable prefix (Claude API):**

| Model | Min prefix |
|---|---|
| `claude-opus-4-8` | **1,024** |
| `claude-opus-4-7` / 4.6 / 4.5 | 4,096 |
| `claude-sonnet-4-6` | 1,024 |
| `claude-haiku-4-5` | 4,096 |

> **Nuance — opus-4-8 = 1,024, not 4,096.** The live caching doc groups `claude-opus-4-8` with the
> 1,024 tier (alongside Sonnet 4.6), **separate** from the Opus 4.7/4.6/4.5 group at 4,096. Older
> cached capability tables said 4,096 for all Opus — **the live doc's 1,024 is authoritative for
> opus-4-8.** Below the threshold the prompt is *silently uncached* (no error).

- ✅ **Verify** a hit via `usage.cache_read_input_tokens > 0`; a write via
  `usage.cache_creation_input_tokens > 0`. If **both are 0**, the prefix was under the minimum.
- ✅ If a prompt falls just short, **pad the cached prefix** up to the threshold — reads are 0.1x.
- Pricing: read **0.1x** base, 5-min write **1.25x**, 1-hour write **2x**.
- Adaptive↔enabled/disabled mode switches **break message cache breakpoints** (system + tools stay
  cached). Keep the thinking mode constant across a cached conversation.

```python
# Pad short prefixes to the model minimum so caching actually engages
MIN_PREFIX = {"claude-opus-4-8": 1024, "claude-sonnet-4-6": 1024, "claude-haiku-4-5": 4096}
assert resp.usage.cache_read_input_tokens or resp.usage.cache_creation_input_tokens, \
    "prefix under min cacheable size — not cached"
```

### Context window & max output

Opus 4.8/4.7, Sonnet 4.6 = **1M** context (200K on Microsoft Foundry for Opus 4.8); Haiku 4.5 = 200K.
On 4.5+ models, `input + max_tokens` over the window is **accepted**, then generation stops with
`stop_reason:"model_context_window_exceeded"` — handle it, don't assume a 400.

- ✅ **Stream when `max_tokens` > ~16000** — a long non-streaming generation risks an SDK HTTP timeout.
- ✅ Use the [token-counting API](./context-management.md) to pre-check before sending.

```python
kwargs = dict(model=route.model, max_tokens=32000, thinking={"type": "adaptive"})
if kwargs["max_tokens"] > 16000:             # stream long generations
    with client.messages.stream(**kwargs, messages=msgs) as s:
        text = s.get_final_message()
else:
    text = client.messages.create(**kwargs, messages=msgs)
```

### Structured outputs

GA on Opus 4.8/4.7/4.6, Sonnet 4.6/4.5, Opus 4.5, Haiku 4.5 (Claude API). Use
`output_config.format` with `type:"json_schema"`. Combinable with strict tool use (`strict:true`).

- ❌ `output_format` at the top level (deprecated) → use `output_config.format`.
- ❌ Citations **+** `output_config.format` together → **400** (citations interleave blocks; schema
  forbids it). Pick one.
- Changing `output_config.format` **invalidates the prompt cache** for that thread — keep it stable.

---

## Anti-patterns

- ❌ Sending `temperature`/`top_p`/`top_k` **or** `thinking.budget_tokens` to Opus 4.8/4.7 → **400**
  (a no-op on Sonnet/Haiku, a hard error on Opus — the asymmetry is the whole point of this file).
- ❌ A trailing `assistant` prefill turn to force a prefix on the 4.6+ line → **400**. Use
  `output_config.format`.
- ❌ `effort` on Haiku 4.5, or `xhigh` on Sonnet 4.6 → unsupported value.
- ❌ Reading `block.thinking` on Opus 4.8 without `display:"summarized"` → silently empty.
- ❌ Assuming opus-4-8 min cacheable prefix is 4,096 (it's **1,024**) → wasted, silently-uncached padding.
- ❌ Date-suffixing an alias (`claude-opus-4-8-2026...`) or hardcoding a model literal in code.
- ❌ Non-streaming a `max_tokens > 16000` call → SDK timeout risk.
- ❌ Bypassing the gateway to hit Anthropic directly (loses observability, billing aggregation, retry).

## Env vars

| Var | Purpose |
|---|---|
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only (route via gateway first) |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 gateway — the default path for direct-Anthropic traffic |
| `CLAUDE_DEFAULT_MODEL` | `claude-opus-4-8` — read by the router, never inlined |

## Curl reference

```bash
# Opus 4.8 frontier call — adaptive thinking + xhigh effort, NO sampling/budget_tokens
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-opus-4-8",
    "max_tokens": 32000,
    "thinking": {"type": "adaptive", "display": "summarized"},
    "output_config": {"effort": "xhigh"},
    "messages": [{"role": "user", "content": "Plan the refactor."}]
  }'
```

## ZDR / batch note

Prompt caching, effort, and adaptive thinking are **ZDR-eligible**. The **Batch API is 50% off but
NOT ZDR-eligible** — never route ZDR-required traffic through batch (see [batch.md](./batch.md)).

---

**Sources** (snapshot `/tmp/claude-docs-snapshot/build-with-claude/`): `adaptive-thinking.md`,
`effort.md`, `extended-thinking.md`, `prompt-caching.md`, `context-windows.md`, `structured-outputs.md`,
`streaming.md`.
