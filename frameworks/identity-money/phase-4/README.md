# Phase 4 — Unified Audit & Compliance Ledger

Closes the identity+money program by giving every actor, resource, and trace a single
queryable history. Builds on `public.audit_events` introduced in Phase 1.

## Scope

- Per-entity timeline view (everything that touched entity X)
- Monthly billable-action rollup (materialized, refreshed hourly)
- Forensic functions for actor / resource / trace lookups
- Per-tenant retention policy with opt-in purge

## Migrations

| File | Purpose |
|------|---------|
| `014_audit_views.sql` | `audit_per_entity_timeline` view + `audit_billable_actions_monthly` materialized view |
| `015_audit_forensic_functions.sql` | `audit.find_actor_history`, `audit.find_resource_history`, `audit.find_chain_for_trace` |
| `016_audit_retention_policy.sql` | `public.audit_retention_policy` + `audit.purge_expired(dry_run)` |

## Dependencies

Phase 1 (`public.audit_events`, `public.tenants`, `public.user_profiles`, `auth.has_scope`).
Independent of Phase 2 and Phase 3 schemas — Phase 4 only reads `audit_events`.

## Operational notes

### Refreshing the rollup

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY public.audit_billable_actions_monthly;
```

Requires the unique index `audit_billable_monthly_uniq` (created in `014`).
Hourly via `pg_cron`, or nightly from the improvement-loop job — pick one.

### Retention

The default is "retain forever." A tenant only ages out events after inserting a row into
`audit_retention_policy` AND a privileged caller invokes `audit.purge_expired(dry_run=false)`.
Always run `dry_run=true` first to confirm row counts.

### Partitioning (recommended at scale)

Once `audit_events` exceeds ~50M rows, switch to monthly range partitioning on `ts`.
This ships as a separate consumer-side migration because partitioning a populated table
requires a maintenance window. Sketch:

```sql
-- Drop old table, recreate as PARTITION BY RANGE (ts), create monthly partitions,
-- INSERT INTO new SELECT * FROM old, then drop old.
```

See `docs/superpowers/specs/2026-05-28-phase-4-unified-audit-design.md` §3 for the full
plan including the rolling-window strategy.

## Querying recipes

```sql
-- Everything actor X did or had done in the last 7 days
SELECT * FROM audit.find_actor_history(
  'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::uuid,
  now() - interval '7 days'
);

-- Every change to payment-source pmsrc_42, all-time
SELECT * FROM audit.find_resource_history('payment_source:pmsrc_42');

-- Full request trace
SELECT * FROM audit.find_chain_for_trace(
  '11111111-2222-3333-4444-555555555555'::uuid
);

-- This month's billable spend events per tenant
SELECT *
FROM public.audit_billable_actions_monthly
WHERE month = date_trunc('month', now())
  AND action LIKE 'spend.%';
```

## Verification

There is no offline schema-check integration in this PR. It is added in a follow-up after
Phases 1-3 land on master (so the script-extension diff stays clean).

To verify against a live Supabase project:

```bash
psql "$SUPABASE_URL" -f 014_audit_views.sql
psql "$SUPABASE_URL" -f 015_audit_forensic_functions.sql
psql "$SUPABASE_URL" -f 016_audit_retention_policy.sql

# Smoke-test the views exist
psql "$SUPABASE_URL" -c "\dv public.audit_*"
psql "$SUPABASE_URL" -c "\dm public.audit_*"
psql "$SUPABASE_URL" -c "\df audit.*"
```
