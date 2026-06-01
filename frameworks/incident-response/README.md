# Incident Response

Severity ladder, routing, and runbook contract for every WAVE app. Pairs with [sentry-instrumentation](../../rules/sentry-instrumentation.md) (signal source) and [job-queue](../../rules/job-queue.md) (DLQ → page).

## Severity ladder

| Sev | Definition | Response time | Routing |
|-----|------------|---------------|---------|
| **P0** | Customer-impacting outage; revenue loss; data integrity at risk | < 5min ack | PagerDuty page + Slack `#incidents-p0` |
| **P1** | Degraded service for a subset; security event under investigation | < 30min ack | PagerDuty page + Slack `#incidents` |
| **P2** | Single-tenant or partial-feature issue; known workaround | next business day | Slack `#alerts` |
| **P3** | Internal-only, cosmetic, doesn't block users | when convenient | Slack `#noise` (auto-archived) |
| **P4** | Informational; FYI events that may matter later | n/a | digest |

## Routing

PagerDuty integration key: `PAGERDUTY_INTEGRATION_KEY`. Slack via `SLACK_WEBHOOK_URL` (per-channel webhook URLs are app-config; the env var is the default).

| Domain | PagerDuty service | Slack channel |
|--------|-------------------|---------------|
| Web / API | `web-oncall` | `#incidents` |
| Webhooks (any publisher) | `webhooks-oncall` | `#incidents` |
| Sandbox runtime | `platform-oncall` | `#sandbox` |
| Spend / billing | `billing-oncall` | `#incidents-billing` |
| Security / auth | `security-oncall` | `#incidents-security` (private) |
| Identity (Phase 1) | `identity-oncall` | `#incidents-identity` |

## Runbook contract

Every alert source has a runbook. Each runbook:

1. **Symptom** — what the user / oncall sees
2. **Probable cause** (top 3, ordered by frequency)
3. **First action** — one command or click, < 60s to execute
4. **Diagnosis** — what to check; what dashboards (linked); what query
5. **Mitigation** — temporary fix to restore service
6. **Root-cause fix** — link to a PR template or follow-up task
7. **Post-mortem template** — link to the doc folder

Runbooks live in each consumer app under `runbooks/<alert-id>.md`. The foundation provides the **template** at [`runbook-template.md`](./runbook-template.md).

## Incident lifecycle

```text
detect → triage → mitigate → fix → post-mortem
```

- **Detect**: alert fires → PagerDuty pages → oncall ack within SLO
- **Triage**: severity assigned + incident channel created (`#inc-<date>-<slug>`)
- **Mitigate**: do the smallest thing that restores service. Document it.
- **Fix**: PR with permanent solution. Tag the incident channel in the PR description.
- **Post-mortem**: P0/P1 require a written post-mortem within 5 business days. Template in `runbooks/post-mortem-template.md`.

## Communication

- **Internal** — incident channel is the single source of truth. Status updates every 15min during active P0/P1.
- **External (customers)** — status page update within 15min of P0/P1 confirmation. Honest, scoped, no speculation about cause.
- **Stakeholder** — after mitigation, a one-paragraph summary in `#leadership` for P0/P1.

## Oncall rotation

- Defined in PagerDuty schedules (`web-oncall`, `webhooks-oncall`, etc.)
- Primary + secondary always staffed for P0/P1 services
- Handoff template: a Slack message in `#oncall-handoff` listing open incidents + watch items

## Anti-patterns

- ❌ Filing a P1 silently (without an incident channel) — loses the audit trail
- ❌ Closing an incident without a follow-up task for the root-cause fix
- ❌ "We can't reproduce" as a post-mortem cause (insufficient — investigate further)
- ❌ Routing all alerts to one channel (signal collapses)
