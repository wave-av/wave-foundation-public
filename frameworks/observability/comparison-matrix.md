# Observability Tool Comparison Matrix

The [WAVE Observability Standard](./README.md) defaults to Sentry + Linear + a generic webhook. That covers ops errors, user-feedback intake, and a fanout sink for Slack/Discord/Intercom.

This doc compares Sentry against the heavier-weight observability platforms (Datadog, Honeycomb, New Relic, Grafana stack) so consumers can pick the right tier without re-deriving the trade-offs.

## What "observability" actually covers

| Concern | Native tool |
|---------|-------------|
| **Errors / crashes** | Sentry (default), Bugsnag |
| **Distributed traces** | Honeycomb, Datadog APM, Tempo (Grafana), Sentry Performance |
| **Metrics (counters/gauges)** | Prometheus + Grafana, Datadog, New Relic |
| **Logs (structured)** | Loki (Grafana), Datadog Logs, BetterStack, plain CloudWatch |
| **Alerts** | PagerDuty, Opsgenie, Discord/Slack webhooks |
| **User session replay** | PostHog (default; analytics-overlapping), FullStory, LogRocket |
| **Real-user monitoring (RUM)** | Datadog RUM, New Relic Browser, Sentry Replay |
| **Synthetic uptime** | Better Uptime, Checkly, Pingdom |

A platform consolidates several of these; the trade-off is cost + lock-in vs. cohesion.

## The five real choices for WAVE scale

| Tool | Strengths | Weaknesses | Cost (typical WAVE) |
|------|-----------|------------|---------------------|
| **Sentry (default)** | Best-in-class error capture, source-mapped stacks, Cloudflare Worker / Bun / Node parity, free tier ~5K errors/mo | Traces + metrics are second-tier; logs require add-on | $0 (free) – $29/mo (Team) |
| **Honeycomb** | Best traces ever invented; high-cardinality query; "Why is THIS request slow?" | Requires instrumenting (OTEL); pricing scales with event volume | $0 (free <20M events) – $130/mo+ |
| **Datadog** | Single-pane-of-glass: metrics + logs + APM + RUM + synthetic | Expensive at scale; lock-in via DD-specific tagging conventions; per-host pricing punishes scale-out architectures | $$$$ |
| **Grafana Cloud** | Open-source-anchored: Prometheus + Loki + Tempo + Pyroscope. Move on/off easily. | Self-serve UX is rougher; alerting is good but not great | $0 (free tier reasonable) – $$$ |
| **New Relic** | Pricing-per-user (now), good APM | UX is dated; tag/instrument is heavy | $0 (free 100GB) – $$$ |

## When to add each tier

**Tier 1 — every spoke ships with:**

- Sentry (errors)
- PostHog (session replay + analytics; PR AL covers feature flags)
- Linear (user feedback → issues)

This is what the WAVE Observability Standard mandates. ~$0–30/mo total.

**Tier 2 — add when one of these is true:**

- p99 latency matters to users (you'll need real distributed traces): **Honeycomb** or **Grafana Tempo**
- Multi-service ownership with SLO/SLI dashboards: **Grafana Cloud** (Prometheus + Loki)
- Compliance demands centralized logs ≥30 days retained: **Grafana Loki** or **BetterStack**

**Tier 3 — single-vendor consolidation:**

- The team consistently bounces between tools (errors → logs → metrics → APM) and the per-incident time-cost > license cost: **Datadog** (acknowledge the lock-in)

## Hard rules (foundation policy)

1. **Sentry is the default; no spoke ships without it.** Enforced by scaffolder + the dogfood `frameworks/observability` doc gate.
2. **Never forward a secret to a third party.** `message` / `extra` payloads are sent verbatim — never include API keys, license keys, raw auth headers, etc. Pass `email_domain`, `plan_id`, `status` — not the credential.
3. **Observability never breaks the path it observes.** Every sink call is `try/catch`; a dead Sentry must not 500 the request. The standard helper enforces this.
4. **One project per spoke in Sentry.** Errors are attributable by service without tag-spelunking. The registry is in [`README.md`](./README.md).

## Cross-references

- [`README.md`](./README.md) — the canonical Observability Standard (Sentry + Linear + webhook)
- [`frameworks/feature-flags/README.md`](../feature-flags/README.md) — PostHog default for flags + replay
- [`frameworks/secrets-management/README.md`](../secrets-management/README.md) — third-party API tokens go in Doppler
- [`docs/threat-model.md`](../../docs/threat-model.md) — secret-leakage threat (A02)
