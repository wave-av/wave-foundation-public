-- Phase 4 — forensic query functions over audit_events.
-- These are read-only convenience functions for compliance / incident response.
-- All return rows from public.audit_events (Phase 1) so they inherit its RLS.
--
-- See: docs/superpowers/specs/2026-05-28-phase-4-unified-audit-design.md §3

BEGIN;

CREATE SCHEMA IF NOT EXISTS audit;

-- find_actor_history: every event where the given actor appears anywhere in actor_chain,
-- bounded by an optional time window. Ordered newest-first.
-- Use case: "show everything user U did or had done on their behalf in the last 30 days."
CREATE OR REPLACE FUNCTION audit.find_actor_history(
  actor uuid,
  since timestamptz DEFAULT NULL,
  until timestamptz DEFAULT NULL,
  max_rows int DEFAULT 1000
)
RETURNS SETOF public.audit_events
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT *
  FROM public.audit_events
  WHERE actor_chain @> ARRAY[actor]::uuid[]
    AND (since IS NULL OR ts >= since)
    AND (until IS NULL OR ts <= until)
  ORDER BY ts DESC
  LIMIT max_rows
$$;

COMMENT ON FUNCTION audit.find_actor_history(uuid, timestamptz, timestamptz, int) IS
'Phase 4 — return audit events touching the given actor (as principal, delegate, or root). RLS-bound.';

-- find_resource_history: every event whose resource matches the prefix, optionally scoped
-- to a tenant. Use case: "trace every change to payment-source X."
-- Resource convention from Phase 1: '<type>:<id>' (e.g. 'payment_source:abc-123').
CREATE OR REPLACE FUNCTION audit.find_resource_history(
  resource_prefix text,
  tenant uuid DEFAULT NULL,
  since timestamptz DEFAULT NULL,
  until timestamptz DEFAULT NULL,
  max_rows int DEFAULT 1000
)
RETURNS SETOF public.audit_events
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT *
  FROM public.audit_events
  WHERE resource LIKE resource_prefix || '%'
    AND (tenant IS NULL OR tenant_id = tenant)
    AND (since IS NULL OR ts >= since)
    AND (until IS NULL OR ts <= until)
  ORDER BY ts DESC
  LIMIT max_rows
$$;

COMMENT ON FUNCTION audit.find_resource_history(text, uuid, timestamptz, timestamptz, int) IS
'Phase 4 — return audit events whose resource starts with the given prefix. RLS-bound.';

-- find_chain_for_trace: reconstruct the full event chain for a single distributed trace.
-- Use case: "what happened during this request, in order?"
CREATE OR REPLACE FUNCTION audit.find_chain_for_trace(
  trace uuid,
  max_rows int DEFAULT 1000
)
RETURNS SETOF public.audit_events
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT *
  FROM public.audit_events
  WHERE trace_id = trace
  ORDER BY ts ASC
  LIMIT max_rows
$$;

COMMENT ON FUNCTION audit.find_chain_for_trace(uuid, int) IS
'Phase 4 — return all audit events for a single trace_id, oldest-first. RLS-bound.';

COMMIT;
