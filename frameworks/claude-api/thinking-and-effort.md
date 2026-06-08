# Claude API: Thinking & Effort

> How WAVE code configures reasoning depth (`thinking`) and compute budget (`effort`) on the current
> Claude model family. The frontier models changed shape: on **Opus 4.8 / 4.7** thinking is *adaptive
> only* and the classic sampling + `budget_tokens` knobs are **removed** (sending them is a hard 400).
> This file is the contract for every spoke; it does not call the API directly — all inference still
> routes through [`../model-routing`](../model-routing/README.md). For Claude **Code** / MCP-secret
> wiring see the sibling `../claude-config/` (different facet — do not duplicate here).

## Models (exact alias strings — NEVER append a date suffix to an alias)

| Alias | Role | Context | Max output | Thinking | Sampling params | `effort` levels |
|-------|------|---------|-----------|----------|-----------------|-----------------|
| `claude-opus-4-8` | default frontier / reasoning | 1M | 128K | adaptive only | **removed (400)** | low/medium/high/**xhigh**/**max** |
| `claude-sonnet-4-6` | balanced | 1M | 64K | adaptive | `temperature` accepted | low/medium/high |
| `claude-haiku-4-5` | fast / cheap | 200K | — | adaptive | `temperature` accepted | low/medium/high |

`claude-opus-4-7` shares Opus-4.8 semantics (adaptive-only, no sampling params, `xhigh`+`max` available).

**Migrate stale IDs** → `claude-opus-4-{7,6,5,1,0}` ⇒ `claude-opus-4-8`; `claude-sonnet-4-{5,0}`/`3-x`
⇒ `claude-sonnet-4-6`; `claude-haiku-3-x` ⇒ `claude-haiku-4-5`. Date-suffixed opus/sonnet aliases
(e.g. `claude-opus-4-6-20260205`) are an anti-pattern — use the bare alias.

## Thinking (Opus 4.8 / 4.7)

- **Adaptive only.** `thinking={"type":"adaptive"}`. The model decides how much to think per turn.
- `thinking={"type":"enabled","budget_tokens":N}` returns **HTTP 400** — `budget_tokens` is fully
  removed on Opus 4.8/4.7. There is no manual budget knob anymore; steer depth via `effort` + prompting.
- **`thinking.display`** defaults to `"omitted"` (reasoning blocks return empty). Set `"summarized"` to
  surface progress to a user/log. Omitted is cheaper to stream and the right default for server-to-server.
- **Sonnet 4.6 / Haiku 4.5:** adaptive thinking supported the same way; `budget_tokens` is *deprecated*
  (ignored, not a 400) but do not send it. `temperature` is still accepted on Sonnet/Haiku.

## Effort (`output_config.effort`)

Compute/quality dial, orthogonal to thinking. `output_config.effort = low | medium | high | max`
(+ `xhigh` on Opus 4.7/4.8). **Default is `high`.** `max` and `xhigh` are **Opus-tier only** — sending
them to Sonnet/Haiku is rejected.

| effort | use when |
|--------|----------|
| `low` | classification, extraction, short structured answers — minimize latency/cost |
| `medium` | routine generation where `high` is overkill |
| `high` (default) | most reasoning/codegen work |
| `xhigh` (Opus) | hard multi-step reasoning; long agentic chains |
| `max` (Opus) | hardest single-shot reasoning; accept the latency/cost |

## Sampling params are GONE on Opus 4.8 / 4.7

`temperature`, `top_p`, `top_k` are **removed** on Opus 4.8/4.7 — sending **any** of them returns
**HTTP 400**. Migrating older code that set `temperature=0` for determinism: delete the param and steer
via prompting ("answer with only the JSON, no prose") + `effort` + structured outputs. They remain
accepted on Sonnet 4.6 and Haiku 4.5, but new code should not depend on them.

## Request-surface changes (apply to Opus 4.8/4.7/4.6 + Sonnet 4.6)

- **No last-assistant-turn prefill.** A trailing `{"role":"assistant", ...}` to constrain the start
  returns **400**. Replace with **structured outputs** (`output_config.format`) or a system instruction.
- **`output_config.format` is canonical.** The old top-level `output_format` param is deprecated.
- **Stream when `max_tokens` > ~16000** — non-streaming risks an SDK HTTP timeout. Use
  `.get_final_message()` (python) / `.finalMessage()` (TS).
- **Handle every `stop_reason`:** `refusal` (read `stop_details.category`),
  `model_context_window_exceeded`, `pause_turn` (server tools — re-issue to continue), `max_tokens`.

## Code — python

```python
# Routed via the model-routing chassis (Anthropic shim on :8088). model comes from routing config,
# NOT hardcoded. Shown with the SDK shape for the Opus 4.8 contract.
from anthropic import Anthropic

client = Anthropic(base_url="http://localhost:8088")  # tier-4 frontier shim; see ../model-routing

resp = client.messages.create(
    model=route.model,                        # e.g. "claude-opus-4-8" — from config, never literal
    max_tokens=4096,
    thinking={"type": "adaptive"},            # adaptive ONLY on Opus 4.8/4.7
    output_config={
        "effort": "high",                     # default; "max"/"xhigh" Opus-only
        "format": {"type": "json_schema", "schema": SCHEMA},  # replaces assistant-prefill
    },
    # NO temperature/top_p/top_k — sending any => HTTP 400 on Opus 4.8/4.7
    # NO thinking.budget_tokens — removed => HTTP 400
    messages=[{"role": "user", "content": "…"}],
)

if resp.stop_reason == "refusal":
    log.warning("refused: %s", resp.stop_details.category)
```

To surface reasoning progress, add `"display": "summarized"` inside `thinking`. Stream long outputs:

```python
with client.messages.stream(model=route.model, max_tokens=32000,
                            thinking={"type": "adaptive"},
                            output_config={"effort": "max"},
                            messages=msgs) as s:
    final = s.get_final_message()
```

## Code — curl

```bash
curl https://localhost:8088/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-opus-4-8",
    "max_tokens": 4096,
    "thinking": {"type": "adaptive", "display": "omitted"},
    "output_config": {"effort": "high"},
    "messages": [{"role": "user", "content": "…"}]
  }'
```

Adding `"temperature": 0`, `"top_p"`, `"top_k"`, or `"thinking":{"budget_tokens":N}` to the above
against Opus 4.8/4.7 returns `400 invalid_request_error`.

## Anti-patterns

- ❌ `thinking={"type":"enabled","budget_tokens":N}` on Opus 4.8/4.7 → 400. Use `{"type":"adaptive"}`.
- ❌ Any `temperature`/`top_p`/`top_k` on Opus 4.8/4.7 → 400. Steer via prompting + `effort`.
- ❌ Trailing assistant-turn prefill to constrain output → 400. Use `output_config.format`.
- ❌ Top-level `output_format` (deprecated) — use `output_config.format`.
- ❌ `effort: "max"`/`"xhigh"` on Sonnet/Haiku → rejected (Opus-tier only).
- ❌ Hardcoding a model alias in code — it comes from [`../model-routing`](../model-routing/README.md) config.
- ❌ Appending a date suffix to an alias (`claude-opus-4-8-2026…`).
- ❌ Calling direct Anthropic without going through the gateway/chassis first (loses observability + billing).
- ❌ Non-streaming with `max_tokens` > ~16000 (SDK timeout risk) — stream + `get_final_message()`.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_API_KEY` | tier-4 direct/frontier (set on the chassis, not the spoke) — see `../model-routing` |
| (model alias) | NOT an env var — comes from routing config; never hardcode |

## Related

- [`../model-routing/README.md`](../model-routing/README.md) — multi-tier Token Leveragizer; all inference routes here first
- [`../model-routing/CHASSIS.md`](../model-routing/CHASSIS.md) — runnable `local_offload` shim (Anthropic `:8088` frontier endpoint)
- [`../observability/README.md`](../observability/README.md) — wrap `stop_reason`/4xx handling in `notifyOps`, never throw on the path
- `../claude-config/` — Claude Code / MCP-secret (Doppler) wiring (sibling facet; may land separately)
- `./prompt-caching.md` — caching prefix rules (cross-linked; see that file for `cache_control` + minimum-prefix nuances)
