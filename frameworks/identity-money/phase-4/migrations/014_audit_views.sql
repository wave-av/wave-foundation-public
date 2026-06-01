-- Phase 4 — unified audit query layer.
-- Phase 1 shipped public.audit_events (append-only). Phase 4 adds query views + forensic
-- functions over it. Partitioning is recommended for production (see README §3) but ships as
-- a separate migration on the consumer side because partitioning a populated table is destructive.
--
-- See: docs/superpowers/specs/2026-05-28-phase-4-unified-audit-design.md §3

BEGIN;

-- Per-entity timeline: every audit event where the entity appears anywhere in actor_chain.
-- Use case: "show me everything user X did or had done to them, ever."
CREATE OR REPLACE VIEW public.audit_per_entity_timeline AS
SELECT
  event_id,
  ts,
  tenant_id,
  actor_chain,
  action,
  resource,
  scope_used,
  before,
  after,
  trace_id,
  -- expose the entity-as-anywhere semantics for client filtering
  actor_chain[1] AS top_actor,
  actor_chain[array_length(actor_chain, 1)] AS root_actor
FROM public.audit_events;

COMMENT ON VIEW public.audit_per_entity_timeline IS
'Phase 4 — per-entity audit timeline. Filter via WHERE actor_chain @> ARRAY[''<uuid>'']::uuid[].';

-- Billable actions monthly: rolls up payment-related audit events per tenant per month.
-- Materialized so the dashboard query is cheap. Refresh: hourly via pg_cron OR the
-- improvement-loop nightly job.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.audit_billable_actions_monthly AS
SELECT
  tenant_id,
  date_trunc('month', ts) AS month,
  action,
  count(*) AS event_count,
  count(DISTINCT actor_chain[array_length(actor_chain, 1)]) AS root_actor_count
FROM public.audit_events
WHERE action LIKE 'spend.%'
   OR action LIKE 'payment.%'
   OR action LIKE 'kyc.%'
GROUP BY tenant_id, date_trunc('month', ts), action;

CREATE UNIQUE INDEX IF NOT EXISTS audit_billable_monthly_uniq
  ON public.audit_billable_actions_monthly(tenant_id, month, action);

COMMENT ON MATERIALIZED VIEW public.audit_billable_actions_monthly IS
'Phase 4 — monthly rollup of payment/KYC audit events per tenant. Refresh hourly via pg_cron or improvement-loop.';

COMMIT;
