# Gateway Integration

> How the Claude API standard binds to [`frameworks/model-routing`](../model-routing/README.md):
> every Anthropic call egresses **through the gateway tier first**, the runnable chassis's frontier
> endpoint **is** the hosted Anthropic API, and the chassis is the layer that makes a request
> Opus-4.8-legal (strip sampling, add adaptive thinking + effort + `cache_control`) before it leaves.
> Consumed read-only via `consume.sh`.

This file is the **seam** between the two standards. [`README.md`](./README.md) owns *how a single
Anthropic request is shaped*; [`model-routing`](../model-routing/README.md) owns *which tier and model
that request lands on*. This doc says **who rewrites what, in what order, on the way out**.

## The one rule

**No call site touches `api.anthropic.com` directly.** A Claude request is emitted toward the routing
substrate and the substrate decides the egress path:

```text
call site  →  local_offload shim (:8088)  →  [local 30B | AI Gateway | OpenRouter | direct Anthropic]  →  human
                     ▲ frontier endpoint = hosted Anthropic
```

- The call site sets `ANTHROPIC_BASE_URL` to the shim (or the gateway), **never** to `api.anthropic.com`.
- The shim's frontier endpoint (`upstream` in `shim/anthropic_frontend.py`, default
  `https://api.anthropic.com`) is the **only** place the hosted Anthropic API is named. That is by
  design: one chokepoint = one place to attach observability, billing aggregation, and the request
  rewrite below.
- Going around the gateway/shim loses observability + billing + the rewrite, so a malformed Opus
  request (stray `temperature`) reaches Anthropic raw and 400s. Both standards forbid it.

## Egress order (matches the Leveragizer)

| Step | Substrate | Owns | This doc's concern |
|------|-----------|------|--------------------|
| 1 | local 30B (Studio) | trivial/first-draft turns | shim serves locally; never reaches Anthropic |
| 2 | AI Gateway | metered multi-provider egress | rewrite MUST already be applied before here |
| 3 | OpenRouter | redundancy | same rewrite contract |
| 4 | **frontier = hosted Anthropic** | Opus/Sonnet/Haiku | rewrite is mandatory here or it 400s |
| 5 | human | all tiers failed | n/a |

The model **alias** and the **tier** come from routing config — never hardcoded at the call site (see
[`model-routing` anti-patterns](../model-routing/README.md#anti-patterns)). This doc assumes routing has
already chosen `claude-opus-4-8` (or sibling) and a frontier egress; it governs the bytes that go out.

## Chassis request-rewrite contract (frontier path only)

When the chassis routes to the **frontier** (hosted Anthropic) for an Opus-tier model, it MUST normalize
the request before forwarding. The call site may emit a generation-neutral body; the chassis makes it
**Opus-4.8/4.7-legal**. Order matters because the cache prefix is byte-matched.

| # | Rewrite | Why | Failure if skipped |
|---|---------|-----|--------------------|
| 1 | **Strip `temperature` / `top_p` / `top_k`** | removed on Opus 4.8/4.7 | any one present → **HTTP 400** |
| 2 | **Strip `thinking.budget_tokens`**; force `thinking={type:"adaptive"}` | `budget_tokens` removed on Opus 4.8/4.7 | `{type:"enabled",budget_tokens}` → **HTTP 400** |
| 3 | **Set `output_config.effort`** from the routing profile (`low\|medium\|high\|max`, `xhigh` Opus-only); default `high` | effort replaces sampling as the steering knob | silent under-/over-spend |
| 4 | **Reject last-assistant-turn prefill**; convert to `output_config.format` or a system instruction | prefills removed on Opus 4.8/4.7/4.6 + Sonnet 4.6 | trailing `assistant` turn → **HTTP 400** |
| 5 | **Inject `cache_control`** on the last SHARED block (tools/system), respecting render order **tools → system → messages**; ≤ 4 breakpoints | byte-stable prefix = cache hit | `cache_read_input_tokens=0`, full re-bill |
| 6 | **Stream when `max_tokens > ~16000`** and collect via `.get_final_message()` / `.finalMessage()` | non-stream long output risks SDK timeout | dropped/timed-out response |

> **Sonnet 4.6 / Haiku 4.5 carve-out:** the rewrite is **model-conditional**. On Sonnet 4.6 `temperature`
> is still accepted (rule 1 is a no-op there); Haiku has no `effort`/`thinking`. The chassis keys the
> rewrite off the resolved alias, not blindly — applying rule 1 only on the Opus tier.

### Known shim gap (flag, don't silently inherit)

The reference shim's neutralizer (`shim/anthropic_frontend.py::_neutral`) currently **forwards
`temperature` verbatim** and applies no rewrite — it only handles the *local-offload* trivial path and
passes everything else upstream raw. That means **rules 1–6 are NOT yet enforced at the frontier by the
shim itself**; today they are the *call site's* responsibility per [`README.md`](./README.md). Wiring
this rewrite into the frontier path (so a neutral body becomes Opus-legal centrally) is the open work
this doc specifies. Until then, treat the table above as the contract every Opus call site must satisfy
*before* `ANTHROPIC_BASE_URL` egress.

### What the rewrite looks like

```text
# call site emits a generation-neutral body (routing already chose claude-opus-4-8):
{ model: <from routing>, messages: [...], temperature: 0.7,
  thinking: {type:"enabled", budget_tokens: 8000}, max_tokens: 32000 }

# chassis, on the Opus frontier path, rewrites to:
{ model: "claude-opus-4-8", messages: [...],            # temperature/top_p/top_k DROPPED
  thinking: {type:"adaptive"},                          # budget_tokens DROPPED
  output_config: {effort: "high", format: <if prefill>}, # effort from profile; prefill→format
  max_tokens: 32000 }                                   # > 16000 → caller streams + finalMessage()
# + cache_control{type:"ephemeral"} on the last shared tools/system block (≤4 breakpoints)
```

The neutral body is portable across tiers (local 30B / Sonnet / Haiku); the Opus-legalization happens
**only** when routing egresses to the Opus frontier. That is the whole point of the seam.

## Mid-conversation & pre-warm (preserve the cached prefix)

- **Pre-warm** at deploy/boot with a `max_tokens:0` request through the same egress path; it writes the
  cache (`content:[]`) so the first real user request reads it. Put `cache_control` on the last shared
  block (system/tools), not on the placeholder user message.
- **Operator instructions mid-conversation**: append a `{role:"system", ...}` entry to `messages[]`
  (beta `mid-conversation-system-2026-04-07`). **Never** edit top-level `system` — that mutates the
  cached prefix and invalidates everything after it.

## Verify the binding works

| Check | Pass | Fail means |
|-------|------|-----------|
| `usage.cache_read_input_tokens` across identical-prefix calls | > 0 | silent invalidator (timestamp/UUID/unsorted JSON/varying tool set) in prefix |
| `usage._served_by` / gateway trace tag | gateway or `local-offload`, never raw direct | a call site bypassed the gateway |
| Opus request with stray `temperature` | rewritten/stripped before egress | 400 from Anthropic = rewrite not applied |
| Sentry frontier-error rate | wrapped in `notifyOps` | unobserved direct call |

## Anti-patterns

- ❌ Pointing `ANTHROPIC_BASE_URL` at `api.anthropic.com` from a call site (bypasses gateway/shim → no observability/billing/rewrite).
- ❌ Hardcoding the model alias at the call site instead of taking it from routing config.
- ❌ Hand-rolled retries with the provider SDK — use the gateway's retry semantics (see [`model-routing`](../model-routing/README.md#anti-patterns)).
- ❌ Forwarding `temperature` / `top_p` / `top_k` / `thinking.budget_tokens` to an Opus-tier frontier (→ 400) — the chassis must strip them.
- ❌ Applying the Opus rewrite unconditionally to Sonnet/Haiku (strips a still-valid `temperature` on Sonnet).
- ❌ Date-suffixing an alias (`claude-opus-4-8-20260...`) anywhere in routing or call config.
- ❌ Setting `cache_control` on the per-request placeholder/user message instead of the last shared block (no prefix to reuse).

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_BASE_URL` | call-site egress target — the `local_offload` shim (`:8088`) or the gateway; **never** `api.anthropic.com` |
| `ANTHROPIC_API_KEY` | tier-4 direct-frontier fallback only (the shim's frontier upstream) — not the default path |
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 gateway egress (owned by [`model-routing`](../model-routing/README.md)) |
| `OLLAMA_API_KEY` | tier-1 local 30B (Studio) — serves trivial turns before any Anthropic egress |

## Related

- [`README.md`](./README.md) — the full Claude API request contract (model IDs, thinking/effort, caching, request surface).
- [`frameworks/model-routing/README.md`](../model-routing/README.md) — the multi-tier Leveragizer; owns tier choice + model selection + retry/escalation.
- [`frameworks/model-routing/local_offload/`](../model-routing/local_offload/) — runnable Anthropic-shaped shim (`:8088`); its frontier `upstream` is the hosted Anthropic API.
- [`frameworks/observability/README.md`](../observability/README.md) — wrap frontier failures in `notifyOps`; never throw from the observe path.
- `frameworks/claude-config/` — Claude Code / MCP / Doppler secrets (sibling facet; cross-link, do not duplicate).
