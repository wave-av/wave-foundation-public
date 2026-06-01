-- Phase 4 — audit retention & partitioning REFERENCE migration.
-- This migration is NON-DESTRUCTIVE: it only creates a helper table to record retention policy
-- and a function to age out events past retention. It does NOT delete any data on its own.
-- Partitioning is recommended for production but ships as a separate, consumer-side migration
-- because partitioning a populated table requires a maintenance window.
--
-- See: docs/superpowers/specs/2026-05-28-phase-4-unified-audit-design.md §3.

BEGIN;

-- Per-tenant retention policy. NULL retention_days = retain forever (default).
-- Compliance-tier tenants set short windows (e.g. PCI = 365); high-trust tenants set NULL.
CREATE TABLE IF NOT EXISTS public.audit_retention_policy (
  tenant_id        uuid PRIMARY KEY REFERENCES public.tenants(id) ON DELETE CASCADE,
  retention_days   int CHECK (retention_days IS NULL OR retention_days > 0),
  reason           text NOT NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       uuid REFERENCES public.user_profiles(id)
);

COMMENT ON TABLE public.audit_retention_policy IS
'Phase 4 — per-tenant retention. NULL = retain forever. Aging-out is opt-in via audit.purge_expired().';

ALTER TABLE public.audit_retention_policy ENABLE ROW LEVEL SECURITY;

-- Only admins (auth.has_scope check) can write; tenant members can read their own row.
CREATE POLICY audit_retention_policy_select
  ON public.audit_retention_policy
  FOR SELECT
  USING (
    tenant_id IN (
      SELECT tenant_id FROM public.user_tenant_memberships WHERE user_id = auth.uid()
    )
  );

CREATE POLICY audit_retention_policy_admin_write
  ON public.audit_retention_policy
  FOR ALL
  USING (auth.has_scope(ARRAY['admin:any'], 'admin:any'));

-- purge_expired: dry-run by default. Returns the (tenant_id, would_delete_count) tuples
-- the caller would purge. Set dry_run=false to actually delete. SECURITY DEFINER so only
-- privileged callers can invoke it (grant EXECUTE narrowly).
CREATE OR REPLACE FUNCTION audit.purge_expired(dry_run boolean DEFAULT true)
RETURNS TABLE(tenant_id uuid, deleted_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, audit
AS $$
DECLARE
  policy_row record;
  cutoff timestamptz;
  delcount bigint;
BEGIN
  FOR policy_row IN
    SELECT p.tenant_id, p.retention_days
    FROM public.audit_retention_policy p
    WHERE p.retention_days IS NOT NULL
  LOOP
    cutoff := now() - (policy_row.retention_days || ' days')::interval;
    IF dry_run THEN
      SELECT count(*) INTO delcount
      FROM public.audit_events e
      WHERE e.tenant_id = policy_row.tenant_id
        AND e.ts < cutoff;
    ELSE
      WITH deleted AS (
        DELETE FROM public.audit_events e
        WHERE e.tenant_id = policy_row.tenant_id
          AND e.ts < cutoff
        RETURNING 1
      )
      SELECT count(*) INTO delcount FROM deleted;
    END IF;
    tenant_id := policy_row.tenant_id;
    deleted_count := delcount;
    RETURN NEXT;
  END LOOP;
END
$$;

COMMENT ON FUNCTION audit.purge_expired(boolean) IS
'Phase 4 — age out audit_events past per-tenant retention. dry_run=true by default.';

-- Lock down execution. Adjust per deployment.
REVOKE EXECUTE ON FUNCTION audit.purge_expired(boolean) FROM PUBLIC;

COMMIT;
