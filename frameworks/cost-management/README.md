# Cost Management Framework

Vendor cost across a WAVE-stack consumer repo (Vercel + Cloudflare + Supabase + Doppler + Sentry + Resend + PostHog + Inngest + AI tokens) is invisible until it's a problem. This framework defines what to track, where the tracking lives, and the threshold pattern that catches a runaway before it's a quarterly-budget event.

## What you actually pay for

| Layer | Common cost drivers |
|-------|---------------------|
| **Hosting** | Vercel bandwidth, build minutes, edge requests; Cloudflare Workers paid plan + duration; serverless function executions |
| **Database** | Supabase row count + storage + egress; Postgres compute hours |
| **Object storage** | R2 / S3 storage GB-mo + egress GB |
| **AI tokens** | OpenAI / Anthropic / Together / Replicate input+output tokens |
| **Observability** | Sentry quota (errors), PostHog (events + recordings), Honeycomb (events) |
| **Email/SMS** | Resend (emails), Twilio (SMS, voice), SendGrid |
| **Identity** | Auth0/Clerk MAU; Supabase Auth users |
| **CI** | GitHub Actions minutes, additional self-hosted runners |
| **Secrets/Misc** | Doppler users, Linear seats, 1Password seats |

## The pattern: monthly cost ledger + per-layer threshold

Each consumer maintains a `cost-ledger.csv` (or similar — Sheet, Notion, Airtable) with monthly per-layer totals:

```text
month,layer,vendor,amount_usd,notes
2026-04,hosting,Vercel,87.50,Pro plan + 50GB bandwidth overage
2026-04,db,Supabase,25.00,Pro plan + 5GB extra
2026-04,ai,Anthropic,412.30,Opus 4.7 + Sonnet 4.6
2026-04,ai,OpenAI,128.40,gpt-4.5-mini + gpt-5
2026-04,observability,Sentry,29.00,Team plan
2026-04,observability,PostHog,0.00,Free tier
2026-04,email,Resend,20.00,50K sends
2026-04,workflow,Inngest,0.00,Free tier
...
```

Per-layer **thresholds** trip an alert when MoM growth exceeds:

| Layer | Threshold | Why |
|-------|-----------|-----|
| AI tokens | ±30% MoM | Most volatile; bug or growth burst hits here first |
| Hosting | ±20% MoM | Bandwidth runaway = misconfigured cache or DDoS |
| Database | ±15% MoM | Storage growth should match user growth; misalignment = bug |
| Observability | ±25% MoM | Spike in errors / replays = quality regression |
| Email/SMS | ±25% MoM | Volume spike = retry storm or bot abuse |

Anything outside threshold opens an issue (template in `frameworks/incident-response/runbooks/cost-spike.md` when wired) before the bill arrives.

## Tracking implementation

Three real options:

| Approach | Pros | Cons |
|----------|------|------|
| **Manual monthly entry** | Free, simple | Easy to skip a month; no real-time signal |
| **Webhook from each vendor + sheet append** | Real-time | Per-vendor webhook plumbing varies; lots of small integrations |
| **OpenCost / Vantage / FinOut** | Full FinOps platform with multi-cloud | $$$; overkill for typical WAVE consumer scale |

The WAVE default for consumers under $5K/mo total spend: **manual monthly entry into a Sheet**, with one cron-tagged Inngest job that pings the on-call engineer if last-month's ledger row is missing.

Once total spend > $5K/mo OR cost-management is a regulatory requirement: **Vantage** (best UX) or **OpenCost** (self-host) is worth the friction.

## AI-token cost: the special case

AI is the single biggest leverage point for cost runaways. Two rules:

1. **Route through the Token Leveragizer** — 5-tier model routing (local 30B → hosted Sonnet → hosted Opus → frontier). The local tier costs $0; route 80% there to keep frontier-tier bills minimal. See `frameworks/model-routing/`.
2. **Per-feature token budgets in dogfood metrics** — when a feature is shipped, its expected tokens/req is recorded. Real usage outside ±30% triggers an issue. The `.dogfood-metrics.ndjson` schema supports this (`token_count`, `model`, `feature_id` fields, when wired).

## Hard rules

1. **Every paid vendor's spend cap is set.** A "no cap" config is the bug; pay-as-you-go can be unbounded by accident.
2. **Per-tenant rate-limit on user-facing paid channels.** Same rule as `frameworks/notifications/README.md` — a bug can burn $10K in SMS in minutes.
3. **AI requests have a hard token cap per call** (default: 32K input + 8K output; raise per-feature with explicit review).
4. **The cost ledger is checked in monthly.** Missing entries trigger a Sentry-routed alert (the only WAVE alert allowed to fire on the 1st of every month).

## Cross-references

- [`frameworks/notifications/README.md`](../notifications/README.md) — rate-limit + idempotency rules apply to paid channels
- [`frameworks/observability/comparison-matrix.md`](../observability/comparison-matrix.md) — tier-2 observability cost trade-offs
- [`frameworks/model-routing/`](../model-routing/) — Token Leveragizer routing for AI cost control
- [`docs/threat-model.md`](../../docs/threat-model.md) — bot abuse (T-flood) → cost spike vector
