# Message Batches API

Asynchronous, half-price processing for large volumes of Messages requests. Submit up to
**100,000 requests or 256 MB** per batch (whichever is hit first); the system processes as fast as
it can, **most batches finish in <1 hour**, hard expiry at **24 hours**. All usage is billed at
**50% of standard prices**. Results stay downloadable for **29 days** after creation.

The catch that drives the governance gate: **Batch is NOT [Zero-Data-Retention (ZDR)] eligible.**
Data is retained under the standard policy. Gate on payload *sensitivity*, not just latency
tolerance. (Prompt caching, by contrast, *is* ZDR-eligible — see [`prompt-caching.md`](./prompt-caching.md).)

## What you get

| Property | Value |
|---|---|
| Price | 50% of synchronous (stacks with prompt-caching discounts) |
| Size cap | 100,000 requests **or** 256 MB, whichever first |
| Typical completion | < 1 hour |
| Hard expiry | 24 hours (unprocessed requests → `expired`, **not billed**) |
| Result retention | 29 days from creation |
| Per-request `params` | full Messages API surface, **per-model-governed** |

Each request carries a developer `custom_id` (unique within the batch) — results come back **out of
order**, so you match on `custom_id`. Requests are processed independently, so you can mix models,
tools, and features in one batch.

## Per-request params are still per-model-governed

`params` is a full Messages creation object. Every per-model constraint from
[`../model-routing/`](../model-routing/) and the **[model-matrix.md](./model-matrix.md)** still
applies *inside* each batched request — the batch envelope does not relax them:

- Default model is the exact string **`claude-opus-4-8`** (never date-suffix an alias). `sonnet-4-6`
  balanced, `haiku-4-5` fast.
- **Opus 4.8/4.7**: thinking is adaptive-only (`thinking.budget_tokens` → **400**);
  `temperature`/`top_p`/`top_k` → **400**. Reasoning depth goes in
  `output_config.effort` (`low|medium|high|max`, +`xhigh`); default `high`; `xhigh`/`max` are
  Opus-only; **`effort` ERRORS on `haiku-4-5`**. `thinking.display` is `omitted|summarized`.
- Last-assistant **prefill** → **400** on opus-4.8/4.7/4.6 + sonnet-4.6; use `output_config.format`
  (`output_format` is deprecated).
- Structured-output and tool-use shapes are unchanged from synchronous.

Validation is **asynchronous**: a bad `params` object is reported per-request when the batch ends,
not at submit time. Verify your request shape against the synchronous Messages API *first*.

### Not supported inside a batch (returns validation error)

| Param | Why |
|---|---|
| `stream: true` | Results come back as one `.jsonl` file, not a stream |
| `speed` (Fast mode) | Tunes synchronous latency; N/A to async |
| `store` / `previous_thread_event_id` (Threads) | Threads are stateful; batches are not |
| `cache_hint` / `context_hint` | Synchronous scheduling hints only |
| `max_tokens: 0` (cache pre-warm) | Ephemeral entry would expire before the follow-up runs |
| `research_preview_2026_02: "active"` | Not on the batch path |

Supported: vision, all server tools (web search/fetch, code execution, MCP connectors), system
messages, multi-turn, **extended thinking**, and most beta features.

## Lifecycle: create → poll → results → cancel

```python
from anthropic import Anthropic
client = Anthropic()  # see Anti-patterns — in WAVE, route via the gateway, not a raw client

batch = client.messages.batches.create(
    requests=[
        {"custom_id": "issue-101",
         "params": {"model": "claude-opus-4-8", "max_tokens": 1024,
                    "messages": [{"role": "user", "content": "Triage issue #101 ..."}]}},
        {"custom_id": "issue-102",
         "params": {"model": "claude-opus-4-8", "max_tokens": 1024,
                    "messages": [{"role": "user", "content": "Triage issue #102 ..."}]}},
    ],
)
# processing_status: in_progress -> ended  (poll the idempotent retrieve endpoint)
while client.messages.batches.retrieve(batch.id).processing_status != "ended":
    time.sleep(60)

for entry in client.messages.batches.results(batch.id):   # streams the .jsonl
    if entry.result.type == "succeeded":
        handle(entry.custom_id, entry.result.message)
    elif entry.result.type in ("errored", "expired", "canceled"):
        requeue(entry.custom_id, entry.result.type)
```

```bash
# Create
curl https://api.anthropic.com/v1/messages/batches \
  --header "x-api-key: $ANTHROPIC_API_KEY" --header "anthropic-version: 2023-06-01" \
  --header "content-type: application/json" \
  --data '{"requests":[{"custom_id":"issue-101","params":{"model":"claude-opus-4-8","max_tokens":1024,"messages":[{"role":"user","content":"Triage #101"}]}}]}'

# Poll until ended
curl https://api.anthropic.com/v1/messages/batches/$ID \
  --header "x-api-key: $ANTHROPIC_API_KEY" --header "anthropic-version: 2023-06-01"

# Stream results (.jsonl) from results_url
curl https://api.anthropic.com/v1/messages/batches/$ID/results \
  --header "x-api-key: $ANTHROPIC_API_KEY" --header "anthropic-version: 2023-06-01"

# Cancel (status -> canceling -> ended; partial results may exist)
curl --request POST https://api.anthropic.com/v1/messages/batches/$ID/cancel \
  --header "x-api-key: $ANTHROPIC_API_KEY" --header "anthropic-version: 2023-06-01"
```

### Status & result-type vocabulary

`processing_status`: `in_progress` → `ended` (or `canceling` → `ended` after a cancel). Read
`request_counts` for the running tally. `results_url` is `null` until processing ends.

| Result type | Billed? | Meaning |
|---|---|---|
| `succeeded` | yes | Message produced; in `result.message` |
| `errored` | **no** | Invalid request or internal error |
| `canceled` | **no** | Cancelled before the request ran |
| `expired` | **no** | Hit the 24h expiry before running |

Endpoints: `POST /v1/messages/batches` (create), `GET /v1/messages/batches/{id}` (retrieve/poll,
idempotent), `GET .../results` (stream `.jsonl`), `POST .../cancel`, `GET /v1/messages/batches`
(list, most-recent first), `DELETE .../{id}` (delete a finished batch).

## The 1h-cache warm-then-fan-out cost trick

Batch + prompt caching discounts **stack**. But cache hits inside a batch are *best-effort* (async,
concurrent execution → observed hit rates 30–98%), and **`max_tokens: 0` pre-warm is not allowed
inside a batch**. So warm the prefix *synchronously first*, then fan out:

1. **Warm** the shared prefix with one **synchronous** `max_tokens: 0` call, writing a **`ttl: "1h"`**
   breakpoint (2× write cost, but paid once). Confirm via `usage.cache_creation_input_tokens > 0`.
2. **Fan out** the batch immediately, with the **identical `cache_control` block** on every request
   so each shares the now-warm prefix.
3. Each batched request pays **0.1× read** on the shared prefix **and** the **50% batch discount** on
   everything — the large stable context (system + tools + pinned docs) is written once and read N
   times at a tenth of input price, at half rate.

Why 1h not 5m: the batch may not drain within the 5-minute window. The 1h TTL keeps the prefix warm
across the whole fan-out. To push hit-rate up: identical breakpoints across all requests, keep the
submission dense, and share as much prefix as possible. Verify with `usage.cache_read_input_tokens`
on the per-request results. Min cacheable prefix: `opus-4-8` = **1024** tokens (live-doc
authoritative; an older cached table said 4096 — use 1024), `sonnet-4-6` = 1024, `haiku-4-5` = 4096.

## WAVE batch-shaped workloads

| Workload | Shape | ZDR note |
|---|---|---|
| **Issue-ops fan-out** | one request per issue (triage/assess/draft) over a shared rubric prefix | internal repo content → batch OK |
| **Evals / bench harness** | one request per test case, shared system+fixtures prefix | synthetic/internal → batch OK; run the 0-cost local loop first (Task #21) |
| **Moderation** | one request per item, shared policy prefix | **gate**: user content may be sensitive → classify before batching |
| **Transcription post-proc** | one request per segment (summarize/label/redact) over a shared instruction prefix | **gate**: PII in transcripts → ZDR-required tenants must NOT use batch |

All four share a large stable instruction/rubric/policy prefix and tolerate latency → ideal for the
warm-then-fan-out trick above. None are realtime; none need streaming.

## Governance gate — sensitivity, not latency

Before routing any workload to batch, answer **"is this payload ZDR-required?"** — *not* "can it
wait an hour?":

- If the tenant/contract requires Zero Data Retention, or the payload carries regulated PII/PHI/
  secrets → **batch is forbidden**, regardless of latency tolerance. Use the synchronous path (which
  can still be ZDR-eligible and still use prompt caching).
- If the payload is internal, synthetic, or already-public, and the work tolerates async → batch is
  the default for cost. Record the sensitivity decision at the call site.
- Prefer the **local 0-cost Studio loop** for internal evals/classification before reaching for the
  hosted batch at all (Leveragizer tier 1; see [`../model-routing/README.md`](../model-routing/README.md)).

## Anti-patterns

- ❌ Routing PII/PHI/regulated or ZDR-contract payloads to batch because "it's just an eval / it can
  wait" — the gate is **data sensitivity**, batch retains data.
- ❌ Calling the Anthropic batch endpoint **directly** from a WAVE spoke. Route via the gateway
  (tier 2) like every other inference call — never bypass it for direct Anthropic.
- ❌ Hardcoding a model in `params`. Resolve the model from routing config / model-matrix.
- ❌ `max_tokens: 0` **inside** a batch (validation error). Warm synchronously, then fan out.
- ❌ Relying on result order — always match on `custom_id`.
- ❌ Assuming submit-time validation. `params` errors surface only when the batch **ends**; shape-check
  against the synchronous Messages API first.
- ❌ A single `max_tokens` over **16,000** in a *synchronous* warmer — stream it (batch results never
  stream, but the warm call still must).
- ❌ Re-downloading the full results blob — **stream** the `.jsonl`.

## Env vars

| Var | Purpose |
|---|---|
| `VERCEL_AI_GATEWAY_API_KEY` | tier-2 route for batch submission (preferred path) |
| `ANTHROPIC_API_KEY` | tier-4 direct fallback only; document the bypass at the call site |
| `OLLAMA_API_KEY` | tier-1 local loop for 0-cost internal evals before hosted batch |

## Related

- [`model-matrix.md`](./model-matrix.md) — per-model `params` constraints enforced inside each request
- [`prompt-caching.md`](./prompt-caching.md) — the warm-then-fan-out prefix; ZDR-eligible (batch is not)
- [`../model-routing/README.md`](../model-routing/README.md) — Leveragizer; local-first; never bypass the gateway

---
Sources: build-with-claude/batch-processing.md; api/messages/batches/create.md; api/messages/batches/results.md; api/messages/batches/retrieve.md; api/messages/batches/list.md; api/messages/batches/cancel.md; api/messages/batches/delete.md
