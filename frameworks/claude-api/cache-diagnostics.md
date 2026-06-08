# Cache diagnostics — the cache-miss → fix playbook

Prompt caching (lever #2 in [`efficiency-levers.md`](./efficiency-levers.md)) only pays off when the
**beginning of the prompt is byte-for-byte identical** to a recent request. One reordered tool, one
timestamp interpolated into the system prompt, or one edited earlier message silently invalidates the
cache — the only native signal is `usage.cache_read_input_tokens` dropping to zero.

**Cache diagnostics** (beta) closes that gap: pass the previous response `id`, and the API reports
*where* the prompt prefix diverged so you fix the root cause instead of guessing. This is the durable
remedy when the console shows a low **cache-read ratio**, low **write-amortization** (cache entries
written then invalidated before reuse), or a tall **Missed tokens by reason** chart.

> Beta. Send header `cache-diagnosis-2026-04-07`. Claude API only (not Bedrock/Vertex). ZDR-eligible —
> fingerprints are hashes + token-count estimates only, never raw prompt content, scoped to your
> workspace, short retention.

## How to read the console panels

| Panel | Healthy | Unhealthy → action |
|-------|---------|--------------------|
| **Cache read ratio** | high (e.g. Opus 4.8 at 96%+) | low → prefix is unstable or entries expire; enable diagnostics to find which |
| **Write amortization** (`reads ÷ writes`) | ≫ 1× (each write reused many times) | ≈ 1× → entries are written then invalidated before reuse — a `*_changed` cause is busting the prefix every turn, OR gaps > TTL (use 1h TTL, lever #5) |
| **Missed tokens / Requests by miss reason** | mostly `Full match` | tall `Messages/Tools/System/Model changed` bars → fix per the table below; tall `Messages changed` on an agentic workload is partly inherent (history grows), so attribute before chasing |

## Cache-miss reasons → what to change

The API reports the **earliest** divergence only — fix it first; later ones may be hidden behind it.

| `cache_miss_reason.type` | Meaning | Fix |
|---|---|---|
| `model_changed` | `model` differs (router / A/B test / fallback picked another). Cache is per-model. | Hold the model constant within a cached conversation. |
| `system_changed` | `system` differs — usually a timestamp/request-id/dynamic value interpolated into it. | Make `system` a **byte-stable constant**; move dynamic data into the first `user` message *after* the cache breakpoint. |
| `tools_changed` | `tools` added/removed/**reordered**, or `input_schema` serialized **non-deterministically**. | Send the same tools every turn in a **fixed order** with **deterministically serialized** schemas (sort keys). |
| `messages_changed` | model+system+tools all match, but an **earlier** message was altered/reordered/removed (truncation, edits, or `tool_result`/assistant blocks re-serialized differently on resend). | Treat history as **append-only**; echo assistant `content` and tool results back **verbatim**. |
| `previous_message_not_found` | No stored fingerprint for that `previous_message_id` (no beta header last turn, different workspace, or too much elapsed time). | Send the beta header **every** turn; keep consecutive turns close in time. |
| `unavailable` | model+system+tools match but another prompt-affecting param differs (`tool_choice`, `thinking`, `context_management`, `output_config`, `output_format`, active `anthropic-beta` set), or the divergence is beyond the comparison horizon. | Keep **all** prompt-affecting params constant for the life of a cached conversation. |

`*_changed` also carries `cache_missed_input_tokens` — a magnitude estimate of lost cacheable prefix
(byte-length derived; treat as indicator, not a billing number).

### diagnostics × usage matrix (when you passed a real `previous_message_id`)

| diagnostics | cache read tokens | Interpretation |
|---|---|---|
| `null` | high | Working as expected — prefix stable, cache hit. |
| `null` | low/zero | Requests match but the entry expired — shorten gaps or use the **1h TTL** (lever #5). |
| `*_changed` | low/zero | **Your bug** — fix the cause `type` indicates. |
| `*_changed` | high | Rare — late divergence but an earlier breakpoint still hit. Low impact. |

## Using it through the WAVE chassis

The chassis `AnthropicEngine` (`frameworks/model-routing/local_offload/shim/engine.py`) forwards
diagnostics as an opt-in passthrough and surfaces the reason — no SDK change needed:

```python
# Turn 1 — opt in (nothing to compare yet)
r1 = engine.complete({"model": "claude-opus-4-8", "messages": msgs, "system": SYSTEM,
                      "diagnostics": {"previous_message_id": None}})
prev = r1["raw"]["id"]

# Turn 2+ — pass the prior response id; the beta header is auto-added, the reason surfaced on the response
r2 = engine.complete({"model": "claude-opus-4-8", "messages": msgs2, "system": SYSTEM,
                      "diagnostics": {"previous_message_id": prev}})
miss = (r2.get("diagnostics") or {}).get("cache_miss_reason")
if miss:
    log.warning("cache miss: %s (~%s tok lost)", miss["type"], miss.get("cache_missed_input_tokens"))
```

The chassis also **serializes request bodies with `sort_keys`**, so a fixed tool list / schema is
byte-identical across turns — removing the `tools_changed` non-determinism cause at the source. Stable
`system` (no interpolated timestamps) and append-only `messages` remain the caller's responsibility; the
gates below catch the statically-detectable cases.

## WAVE remediation order (highest leverage first)

1. **Attribute, don't guess.** Turn on diagnostics on the suspect path; read the `type`. A tall
   *Messages changed* bar on an agentic loop is largely inherent (history grows) — confirm before chasing.
2. **`model_changed`** → pin the model for the conversation (don't let the router swap mid-thread).
3. **`system_changed`** → move any timestamp/id/dynamic value out of the cached `system` block into the
   first post-breakpoint `user` message.
4. **`tools_changed`** → fixed tool order + deterministic schema serialization (the chassis `sort_keys`
   handles serialization; keep the *list* stable).
5. **`messages_changed`** → append-only history; echo prior `content`/`tool_result` verbatim.
6. **expired (diagnostics `null`, zero reads)** → 1h cache TTL (lever #5) for bursty traffic with > 5 min gaps.

## See also
- [`prompt-caching.md`](./prompt-caching.md) — the caching mechanics + breakpoint placement
- [`efficiency-levers.md`](./efficiency-levers.md) — levers #2 (caching), #5 (1h TTL), #14 (this)
- Live doc: `https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics`
