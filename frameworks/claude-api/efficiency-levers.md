# Claude API efficiency levers — the cost cheatsheet

One place that enumerates **every** cost/latency lever, what it saves, how to turn it on, and when **not**
to. The reference chassis (`frameworks/model-routing/local_offload/shim/engine.py`) implements the
request-shaping ones; the routing ones live in `frameworks/model-routing`. Adopt top-down: the biggest
wins are #1–#3.

## Cost-optimization priorities — ranked by REAL spend (Admin-API audit 2026-06-04)

A 7-day org audit (`GET /v1/organizations/usage_report/messages` + `/cost_report`, see `admin-api.md`)
showed **~$7.4k/7d**, ~all interactive Claude Code on Opus 4.8/4.7. Caching was already maxed
(**99.5% read-ratio, 8.85× write-amortization**). Fix in this order (biggest $ first):

> ⚠️ **The 1M context window is NOT a price tier.** Live pricing ("Long context pricing"): Opus 4.8/4.7/4.6
> + Sonnet 4.6 bill the **full 1M window at standard rates** — "a 900k-token request is billed at the same
> per-token rate as a 9k-token request." Empirically confirmed from `cost_report`: Opus 4.8 cache-read at
> >200k = **exactly $0.50/MTok** (= base ×0.1), output >200k = **exactly $25/MTok** (= base). The
> "…- 1M Context" billing lines are **informational labels, not a premium.** Dropping `[1m]`→200k saves $0.

1. **Model tier — the biggest controllable lever.** Audit was **100% Opus, $0 Sonnet/Haiku.** Sonnet 4.6 is **~40% cheaper across the board** ($3/$15 + $0.30 cache-read vs Opus $5/$25 + $0.50); Haiku 4.5 ~80% cheaper ($1/$5); local = $0. Route routine/mechanical work to Sonnet/Haiku/local (the Leveragizer, lever #1 below); reserve Opus for genuinely hard reasoning. **Don't silently downgrade a frontier path without an eval gate.**
2. **Context VOLUME (not window size).** The bill ≈ tokens × rate, and rate is already minimized (caching + tier). 5.58B cache-read tokens/7d means huge prompts are re-read **every turn** at $0.50/MTok (~$2.8k/7d just in reads) + 452M cache **writes** ($6.25/MTok 5m, the single biggest line). Fewer tokens in context = fewer billed tokens regardless of caching: load fewer files, `/clear` between tasks, lean on compaction, prune system bloat.
3. **service_tier (was 100% `standard`, 0% batch/flex).** Non-realtime/bulk work (eval sweeps, offline agents) → **Batch API (50% off:** Opus $2.50/$12.50); latency-tolerant calls → **flex.** N/A for interactive coding (can't queue) — but a real win for platform/agent batch workloads.
4. **Avoid silent premiums.** **Fast mode** (`/fast`) is **2× on Opus 4.8** ($10/$50) — the audit confirmed standard $25/MTok output, so it's OFF; keep it off unless speed is worth 2×. **`inference_geo:"us"`** adds **1.1×** — stay on `global` (default) unless data residency requires US.
5. **Caching** — already near-optimal (99.5% / 8.85×); enforced fleet-wide by the now-blocking `claude-api-cache` gate. Keep it; don't regress.

**Attribution:** commingled traffic hides leaks. Put platform/agent traffic in a **separate workspace** from interactive Claude Code so `cost_report group_by[]=workspace_id` shows each clearly. Re-run the audit monthly with the Admin key (`ANTHROPIC_ADMIN_API_KEY`, Doppler `wave/prd`).

| # | Lever | Saves | Enable | Don't, when |
|---|-------|-------|--------|-------------|
| 1 | **Model-downgrade routing** | Most of the bill — never pay Opus rates for a Haiku-class task | route cheap→escalate (`frameworks/model-routing`); local tier for internal traffic | a known-hard task that will just round-trip and escalate anyway |
| 2 | **Prompt caching** | ~0.1× input price on a repeated stable prefix | `cache_control:{type:"ephemeral"}` on the **last stable** block (tools→system→messages render order: one breakpoint on the last `system` block also caches the tools before it) | the prefix genuinely varies per request (you'd only pay the write premium) — mark `cache-exempt` |
| 3 | **`output_config.effort`** | Fewer/again-consolidated tool calls + less preamble at lower effort | `effort: low\|medium\|high\|xhigh\|max` (default `high`; per-route — `low` for extraction/summary, `high`/`xhigh` for reasoning/code) | correctness-critical work — keep `high`/`max` |
| 4 | **Streaming (>~16K out)** | Avoids SDK/HTTP timeouts on long output (not $, but prevents wasted full retries) | `stream:true` + accumulate (chassis auto-streams when `max_tokens > 16000`) | tiny responses — needless complexity |
| 5 | **1h cache TTL** | Keeps a prefix warm across gaps > 5 min (2× write cost, 0.1× reads) | `cache_ttl:"1h"` → `cache_control:{type:"ephemeral",ttl:"1h"}` | steady traffic with < 5 min gaps — the 5 min default already hits |
| 6 | **`service_tier:"flex"`** | Lower price on latency-tolerant calls | `service_tier:"flex"` (passthrough) | user-facing/interactive paths — flex may queue |
| 7 | **`context_management` (clear_tool_uses)** | Drops stale tool results server-side so you stop re-sending them → fewer input tokens/turn | `context_management:{edits:[{type:"clear_tool_uses_20250919"}]}` + beta header | short conversations — nothing to clear |
| 8 | **Compaction (beta)** | Auto-summarizes history near the context limit instead of erroring/truncating | beta `compact-2026-01-12`; **append `response.content` (not just text)** each turn | one-shot calls |
| 9 | **`task_budget` (beta)** | The model self-moderates a whole agentic loop against a token countdown (≠ `max_tokens`) | `task_budget:{type:"tokens",total:N}` (min 20,000) + beta `task-budgets-2026-03-13` (chassis: pass `req["task_budget"]`, header auto-added) | single-shot / non-agentic calls |
| 10 | **Batch API** | **50% off** input+output for non-realtime bulk work | `POST /v1/messages/batches` (`batch.md`) | latency-sensitive work; tiny volumes; **not** for workloads that already run on a local model ($0) |
| 11 | **Token counting** | Pre-flight sizing → avoid over-budget 400s / pick the right cache breakpoint | `POST /v1/messages/count_tokens` | hot paths where the extra round-trip costs more than it saves |
| 12 | **Files API** | Upload once, reference by ID instead of re-sending bytes every call | `POST /v1/files` (`files-and-media.md`) | a file used once |
| 13 | **Structured outputs** | Kills regex parsing, "respond in valid JSON" prompting, and malformed-JSON retry loops (fewer round-trips, fewer wasted output tokens) | `output_config:{format:{type:"json_schema",schema:{…}}}` + `strict:true` on tools (chassis: pass `req["response_format"]` → mapped to `output_config.format`, **all** models). Every `object` needs `additionalProperties:false`. | free-form prose answers — a schema only adds friction |
| 14 | **Cache diagnostics (beta)** | Turns a silent cache miss into an attributed root cause (model/system/tools/messages_changed) so you fix the real divergence instead of guessing — protects levers #2/#5 | `diagnostics:{previous_message_id:<prior id\|null>}` + beta `cache-diagnosis-2026-04-07` (chassis: pass `req["diagnostics"]`, header auto-added, reason surfaced as `out["diagnostics"]`) | a steady high cache-read ratio with no mystery misses — it's a diagnostic, not a steady-state cost |

See [`cache-diagnostics.md`](./cache-diagnostics.md) for the miss-reason → fix playbook — the durable remedy for a low cache-read ratio or low write-amortization (the chart you read on the console's *Missed tokens by reason* / *Write amortization* panels).

## Opus 4.8 request-shape constraints (not levers, but required)
- **No `temperature`/`top_p`/`top_k`** on Opus 4.8/4.7 → HTTP 400. Steer via `effort` + `thinking:{type:"adaptive"}`.
- **`budget_tokens` removed** on Opus 4.7/4.8 → adaptive thinking only.
- **Min cacheable prefix:** Opus 4.8 + Sonnet 4.6/4.5 = **1,024** tokens; Opus 4.7/4.6/4.5 + Haiku 4.5 = 4,096. Below it, caching silently no-ops — verify with `usage.cache_read_input_tokens`.
- Structured outputs: every `object` in a JSON schema needs `"additionalProperties": false` (see `model-matrix.md`).

## What WAVE has wired today
- **Live in prod:** model-downgrade routing, prompt caching (dispatch frontier #224 + gateway passthrough + chassis), per-route `effort` (#242), streaming.
- **Chassis surface (opt-in passthrough):** `service_tier`, `context_management`, `betas`, `task_budget`, `response_format` (structured outputs → `output_config.format`), `diagnostics` (cache diagnostics), 1h cache TTL. The chassis also serializes request bodies with `sort_keys` so a fixed tool/schema is byte-identical across turns (removes a `tools_changed` miss cause at the source).
- **Documented / situational:** Batch (no current Anthropic bulk workload — internal evals run on a local model at $0), token counting, Files API.
- **Enforced fleet-wide:** the `claude-api-cache` + `claude-api-shape` gates (inherited via `foundation-gate.yml@v1`) keep new code caching + Opus-shape-correct.
