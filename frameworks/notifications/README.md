# Notifications Framework

Notifications cross four orthogonal axes: who pays, who sees, urgency tier, and channel type. Picking the right tool per axis avoids the common mistake of "one transactional email service for everything" (which makes lifecycle marketing painful) or "one Slack webhook for everything" (which makes per-user routing painful).

## Axes

| Axis | Options |
|------|---------|
| **Audience** | end-user, internal team, oncall engineer, system (machine-to-machine) |
| **Urgency** | now (page), soon (Slack/Discord), eventually (email digest), archival (log only) |
| **Channel** | email, SMS, push, in-app, Slack/Discord/Teams, voice |
| **Relationship** | transactional (1:1 trigger), marketing (lifecycle / broadcast), operational (system event) |

A "the deploy failed" notification is internal-team / now / Slack / operational. A "your invoice is ready" notification is end-user / eventually / email / transactional. These belong in different services.

## Tool matrix

| Tool | Best for | Cost | Notes |
|------|----------|------|-------|
| **Resend** | Transactional email (WAVE default) | $0 (3K/mo free) – $20/mo (50K) | React Email components, deliverability-tuned, audit log |
| **Knock** | Cross-channel orchestration (email + push + SMS + in-app + Slack) with per-user preferences | $0 (free <10K MAU) – $$$ | Worth it when end-users get notified across ≥3 channels and want preference control |
| **Twilio Programmable Messaging** | SMS (transactional or OTP) | per-msg | Pure SMS; not the right shape for full multi-channel orchestration |
| **Twilio Verify** | OTP / 2FA delivery | per-msg | Best-in-class deliverability and bot-detection for verification flows |
| **Slack webhook** | Internal team alerts | $0 | The simplest path. One incoming webhook per channel. Never expose to end-users. |
| **Discord webhook** | Internal/community team alerts | $0 | Same shape as Slack; use for communities + lighter orgs |
| **PagerDuty / Opsgenie** | Oncall escalation (now-now-now) | $$$$ | Pays for itself the first 3am page-out. Worth it once you have rotation. |
| **SES / SendGrid (legacy)** | Transactional email at extreme scale | usage-based | Resend has caught up; SES still cheaper at >1M/mo. |
| **Intercom** | End-user support inbox + automated lifecycle messages | per-user, $$$ | Worth it when CS is a team function. |
| **APNS / FCM / OneSignal** | Mobile push | $0 (raw) | Knock wraps these with preference centers. |

## The WAVE default

| Use case | Tool |
|----------|------|
| End-user transactional email | **Resend** |
| End-user 2FA / OTP | **Twilio Verify** |
| End-user multi-channel orchestration | **Knock** (when needed) |
| Internal alerts (deploy, threshold, etc.) | **Slack webhook** + **Sentry → Slack integration** |
| Oncall escalation | **PagerDuty** (when on rotation) |
| User support inbox | **Intercom** (when CS is a team function) |

## Hard rules

1. **Never send a secret in notification payload.** Same rule as observability — `email_domain`, `plan`, `status` are fine; tokens / keys / raw auth headers are forbidden. See `frameworks/secrets-management/README.md`.
2. **Per-tenant rate-limit on user-facing channels.** A bug in a notification job can blast 10K SMS at $0.01 each in seconds. Rate-limit by recipient + per-tenant cap.
3. **Idempotency keys for transactional sends.** Webhook retries are real; the same `order.shipped` event MUST NOT send twice. Use `notification_idempotency_key = sha(event_id + recipient + template)`. See `frameworks/events-inngest-workflows/idempotency.md` (when wired).
4. **DKIM + SPF + DMARC on email sends.** Cold-start deliverability without this is single-digit %. Resend automates; SES requires manual setup.
5. **Preference center for non-transactional.** Every marketing/lifecycle email needs an unsubscribe path that actually unsubscribes. Knock handles this; Resend requires explicit handling.

## Wiring (typical WAVE consumer)

```ts
// Transactional email
import { Resend } from "resend";
const resend = new Resend(env.RESEND_API_KEY);  // Doppler-injected
await resend.emails.send({
  from: "noreply@wave.online",
  to: user.email,
  subject: "Your invoice",
  react: <InvoiceEmail user={user} invoice={inv} />,  // React Email component
});

// Internal alert
await fetch(env.SLACK_OPS_WEBHOOK, {
  method: "POST",
  body: JSON.stringify({ text: `Deploy failed: ${ref}` }),
});

// Oncall page (PagerDuty Events API v2)
await fetch("https://events.pagerduty.com/v2/enqueue", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    routing_key: env.PAGERDUTY_INTEGRATION_KEY,
    event_action: "trigger",
    payload: { summary: "Edge 5xx > 1%", severity: "critical", source: "edge-worker" },
  }),
});
```

## Cross-references

- [`frameworks/observability/README.md`](../observability/README.md) — Sentry → Slack for ops errors
- [`frameworks/observability/comparison-matrix.md`](../observability/comparison-matrix.md) — when to add PagerDuty (Tier 1 → Tier 2)
- [`frameworks/secrets-management/README.md`](../secrets-management/README.md) — API tokens in Doppler
- [`frameworks/feature-flags/README.md`](../feature-flags/README.md) — gate notification rollouts (e.g., new template at 10%)
- [`docs/threat-model.md`](../../docs/threat-model.md) — secret-leakage threat applies to notification payloads too (A02)
