# Workflow Engines Framework

When async, durable, multi-step orchestration is needed — billing reconciliation, video encoding pipelines, retried external API calls, multi-step agent task graphs — the choice of workflow engine shapes a lot of downstream complexity.

This doc compares the five real options for WAVE-stack repos and codifies which to pick.

## What "workflow engine" means here

A workflow engine provides:

1. **Durable execution** — the workflow survives process crashes, deploys, and node failures; state is persisted
2. **Retry with backoff** — failed steps retry with policy, not ad-hoc try/catch
3. **Step composition** — `step1 → step2 → fanout → join → step3` with each step idempotent
4. **Time-based wait** — sleep for hours/days without burning compute
5. **Observability** — every run/step inspectable in a dashboard

Without a workflow engine you build these capabilities ad-hoc per workflow and they decay. With one, every workflow inherits them.

## When you need a workflow engine

You probably need one when:

- A single user action triggers > 3 async steps with conditional branches
- Steps fail intermittently and need retry (external API, video encoding, payment confirm)
- A step needs to "wait 24h then check status" (otherwise = polling loop)
- Multiple workflows compose (`order → invoice → notify` plus `invoice → reconcile`)

You probably do NOT need one when:

- The async work is fire-and-forget (just use a queue: SQS, Redis, Trigger.dev simple task)
- The work is purely request-response (just use the request handler)

## Tool matrix

| Tool | Best for | Cost | Notes |
|------|----------|------|-------|
| **Inngest (WAVE default)** | TypeScript-native workflows, event-driven, free tier covers most | $0 (free 50K steps/mo) – $$$ | Best DX for the WAVE stack. Workflows are typed code that look like normal functions. Replay, fan-out, throttle built-in. |
| **Trigger.dev** | Same shape as Inngest, slightly different DX | $0 (free 5K runs/mo) – $$ | Excellent for jobs-style work; v3 is a real durable runtime. Choose if Inngest dashboard doesn't fit. |
| **Temporal** | Multi-language polyglot, enterprise scale, complex sagas | Self-host (free) / Cloud ($$$) | Heaviest setup. Worth it at 100M+ workflows/mo with cross-language teams. Workflows are imperative code with replay-safe coroutines. |
| **AWS Step Functions** | AWS-only stack, JSON-defined workflows | $25/M state transitions | If you're already deep in AWS. JSON definition is verbose for complex logic. |
| **GitHub Actions reusable workflows** | CI/CD orchestration only | $0 (free for public repos) | Use for build/test/deploy chains. NOT for runtime workflows. |
| **Cron + queue (DIY)** | Simple, low-volume async | $0 | Fine for "send digest emails Mondays at 9am." Avoid for anything multi-step. |

## The WAVE default: Inngest

Why:

1. TypeScript-native — workflows look like normal functions, with type-checked event schemas
2. Free tier (50K steps/mo) covers typical WAVE-stack volume
3. Event-driven model fits webhook → workflow naturally
4. Built-in observability dashboard with replay
5. Already used in several WAVE consumers

Trade-off: Python-heavy teams might prefer Temporal (multi-lang). For pure TS/JS, Inngest wins on DX.

## Hard rules

1. **Every workflow step is idempotent.** Inngest replays on failure; if `charge_card` runs twice it must charge once. Use idempotency keys keyed on `event_id + step_name`. See `frameworks/events-inngest-workflows/idempotency.md` (when wired).
2. **No raw secrets in workflow payloads.** Steps receive `event.data`; never put rail keys, license keys, raw auth headers in `data`. Pass `customer_id` and look up the secret server-side.
3. **Time-based waits use the engine's wait primitive**, not `setTimeout`. `step.sleepUntil(date)` survives deploys; `setTimeout` does not.
4. **Workflow definitions are versioned.** Changing a workflow's step shape mid-run requires a new version; old in-flight runs continue on the old version until drained.

## Workflow vs queue vs cron

A common mistake: picking a workflow engine for fire-and-forget work, or a queue for multi-step durability.

| Need | Use |
|------|-----|
| "Send this email, don't care when" | Queue (SQS, Upstash QStash, Trigger.dev task) |
| "Run this Monday 9am" | Cron (vendor or your own scheduler) |
| "Charge card → if success, ship → wait 24h → check arrival → notify" | **Workflow engine** |
| "Build, test, deploy on PR merge" | GitHub Actions |
| "Process this webhook NOW, retry on fail" | Workflow engine OR webhook handler with manual retry queue |

## Cross-references

- [`frameworks/notifications/README.md`](../notifications/README.md) — sends triggered from workflow steps must be idempotent (rule 1)
- [`frameworks/secrets-management/README.md`](../secrets-management/README.md) — payload-secret rule (rule 2)
- [`frameworks/observability/README.md`](../observability/README.md) — workflow failures route to Sentry like everything else
- [`docs/threat-model.md`](../../docs/threat-model.md) — workflow-event tampering is a real threat (validate event shape + signature)
