# Runbook: <alert-id>

> Copy this template for each alert source. Keep runbooks under 200 lines.

## Symptom

What the user sees. What the oncall sees in their alert. Include the literal alert text.

## Probable causes

1. **Most common** — short description
2. **Second** — short description
3. **Third** — short description

## First action (< 60s)

The one command or click that buys you time to investigate. Example:

```bash
# Rotate the affected DLQ
gh workflow run replay-dlq.yml -f queue=webhooks-stripe
```

## Diagnosis

What to check, in order:

| Check | How | What "bad" looks like |
|-------|-----|------------------------|
| Sentry error rate | [link to Sentry query](https://sentry.io/...) | > 5%/5min |
| Database connections | [Grafana dashboard](https://grafana.../app-db) | > 80% pool |
| Upstash latency | [Grafana](https://grafana.../upstash) | p99 > 100ms |
| Queue depth | [Grafana](https://grafana.../queues) | > 1000 |

## Mitigation

Temporary actions to restore service. Reversible.

- Option A: scale workers — `vercel env set ... && vercel redeploy`
- Option B: disable feature flag — `...`
- Option C: failover to backup — `...`

## Root-cause fix

Link to a PR template or issue tracker. The fix is owned by `<team>`.

## Post-mortem

Required for P0/P1. Use [`post-mortem-template.md`](./post-mortem-template.md).

## Related

- Linked alerts: ...
- Linked runbooks: ...
- Dashboards: ...
