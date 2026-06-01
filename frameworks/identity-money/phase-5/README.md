# Phase 5 — Active Authorization & Anomaly Detection

The final identity+money phase. Where Phase 4 made the audit log **queryable**,
Phase 5 makes it **actively observable** — turning the static ledger into a
real-time signal that gates decisions, files alerts, and (optionally) revokes
access. All three layers are shipped.

Full design: [`docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md`](../../../docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md).

## The three layers

| Layer | What | Phase | Status |
|-------|------|-------|--------|
| 1 — anomaly rules (declarative) | `anomaly_rules` + `anomaly_findings` + evaluator | 5.1 | shipped |
| 3 — alerting (passive) | route findings to Sentry / Linear / Slack | 5.2 | shipped |
| 2 — enforcement (active) | `actor_blocks` + block-aware gate + auto-revoke | 5.3 | shipped |

Ship order was 5.1 → 5.2 → 5.3 so alerting exists before any automated enforcement.

## Migrations

| File | Layer | Purpose |
|------|-------|---------|
| `017_anomaly_rules.sql` | 1 | rule catalog + RLS (read: authenticated; write: owner/admin) + 3 seed rules |
| `018_anomaly_findings.sql` | 1 | per-firing rows, tenant-attributed + per-tenant read/resolve RLS + unresolved index |
| `019_actor_blocks.sql` | 2 | `actor_blocks` + `auth.is_actor_blocked()` + `auth.actor_can()` + `block_next` trigger |
| `020_rule_evaluator.sql` | 1 | `public.evaluate_anomaly_rules()` — `SECURITY DEFINER`, idempotent within a window |
| `021_pg_cron_install.sql` | 1 | consumer opt-in `cron.schedule('anomaly-eval','*/1 * * * *')`; no-ops without pg_cron |
| `022_anomaly_alert_routing.sql` | 3 | `alerted_at` + `anomaly_findings_to_alert` view + `mark_anomaly_alerted()` |
| `023_auto_revoke.sql` | 2 | `auto_revoke_actor()` + `auto_revoke_scope` trigger; extends `identity_links.event` |

Migrations apply in lexical order; the numbering keeps `019` (blocks) adjacent to the
evaluator (`020`) it pairs with.

## Dependencies

- Layer 1 (017/018/020/021): Phase 1 (`audit_events`, `tenants`, `user_tenant_memberships`).
- Layer 2 blocks (019): Phase 1 + `auth.has_scope`. Auto-revoke (023): **Phase 2**
  (`user_credentials`, `identity_links`, the last-credential guard).
- Layer 3 (022): Layer 1 tables + `frameworks/observability`.

## Seed rules (017)

| Name | Pattern | Window | Threshold | Severity | Action |
|------|---------|--------|-----------|----------|--------|
| `hourly_spend_cap` | `spend.allowed` sum | 1 hour | $10,000 | blocking | block_next |
| `payment_source_enumeration` | distinct `payment_source.read` | 5 min | 100 | warning | alert |
| `admin_scope_from_non_admin` | `admin.%` count | 24 hours | 1 | blocking | auto_revoke_scope |

Rules are global; every **finding** is attributed to the tenant whose `audit_events`
tripped it (per-tenant evaluation — cross-tenant patterns are Phase 6).

## Layer 1 — detection (evaluator)

`pg_cron` (or your own scheduler) calls `public.evaluate_anomaly_rules()` every 60s.
It loops enabled rules, aggregates matching `audit_events` inside each rule's
`window_span`, groups by `(tenant, leaf actor)`, and inserts a finding wherever the
aggregate crosses the threshold. Idempotent within a window — an overlapping finding
for the same `(rule, tenant, actor)` suppresses a re-fire.

## Layer 2 — enforcement

| Rule action | Effect |
|-------------|--------|
| `alert` | finding only (Layer 3 routes it); no enforcement |
| `block_next` | `019` trigger inserts `actor_blocks` (TTL = rule's `window_span`); `auth.actor_can()` refuses the actor's next request |
| `auto_revoke_scope` | `023` trigger disables the actor's credentials (all but the oldest, to respect the last-credential guard), logs `credential_auto_revoked` to `identity_links`, AND blocks the actor |

Enforcement is **block-aware, not scope-rewriting**: the existing IMMUTABLE
`auth.has_scope` is untouched. Paths that must honor blocks call the new
`auth.actor_can(actor, scopes, required)` (= `has_scope AND NOT is_actor_blocked`).
Both block and revoke are **reversible** by an admin (lift the block / re-enable the
credential).

## Layer 3 — alerting

Consumer-side; Postgres only tracks routing state. A poller reads
`public.anomaly_findings_to_alert`, routes per
[`frameworks/observability/anomaly-routes.yml`](../../observability/anomaly-routes.yml),
then calls `public.mark_anomaly_alerted(finding_id)`.

| Severity | Sinks |
|----------|-------|
| `info` | (none) — recorded only |
| `warning` | Sentry |
| `blocking` | Sentry + Linear (SECURITY) + Slack (`#security-incidents`) |

Every sink is flag-gated off (no env → no behavior); only the `payload_allowlist`
fields leave the system (evidence rows are never forwarded).

## Verification

```sql
-- seed ruleset
SELECT name, severity, action FROM public.anomaly_rules ORDER BY name;

-- detection: flood a test tenant, run the evaluator, confirm a finding
INSERT INTO public.audit_events (action, actor_chain, tenant_id, resource, scope_used, after)
  SELECT 'spend.allowed', ARRAY[gen_random_uuid()], '<tenant>', 'pmsrc_' || i,
         'billing:spend:any', jsonb_build_object('amount', 500)
  FROM generate_series(1, 50) i;
SELECT public.evaluate_anomaly_rules();
SELECT r.name, f.measured_value, f.severity
FROM public.anomaly_findings f JOIN public.anomaly_rules r ON r.id = f.rule_id
ORDER BY f.ts DESC LIMIT 5;

-- enforcement: a block_next finding blocks the actor's gate
SELECT auth.actor_can('<actor>', ARRAY['billing:spend:any'], 'billing:spend:any');  -- false while blocked

-- alerting queue
SELECT rule_name, severity FROM public.anomaly_findings_to_alert;
```

Offline file conformance:

```bash
bash scripts/check-identity-schema.sh --offline --phase 5
```
