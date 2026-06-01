-- Phase 1 — audit envelope.
-- Every state-changing operation across the program emits a row of this shape.
-- Phase-4 ships the unified query layer; Phase 1 ships the table + helper.
--
-- See: docs/superpowers/specs/2026-05-28-identity-money-program-overview.md §2.5

BEGIN;

CREATE TABLE IF NOT EXISTS public.audit_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ts timestamptz NOT NULL DEFAULT now(),
  actor_chain uuid[] NOT NULL,         -- top-to-leaf: orchestrator → agent → human
  action text NOT NULL,                -- dotted: "agent.token_exchange.granted"
  resource text NOT NULL,              -- "<table>/<id>" or "<service>:<op>"
  before jsonb,                        -- prior state or NULL on create
  after jsonb,                         -- new state or NULL on delete
  scope_used text,                     -- the scope that authorized this op
  -- tenant FK with ON DELETE RESTRICT: audit rows must never become orphans.
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  dpop_thumbprint text,                -- JWT cnf.jkt or NULL
  request_id uuid,
  trace_id uuid,
  CHECK (cardinality(actor_chain) >= 1)
);

CREATE INDEX IF NOT EXISTS audit_events_tenant_ts_idx ON public.audit_events(tenant_id, ts DESC);
CREATE INDEX IF NOT EXISTS audit_events_actor_idx ON public.audit_events USING gin(actor_chain);
CREATE INDEX IF NOT EXISTS audit_events_action_idx ON public.audit_events(action);

-- audit_events is append-only by design. No UPDATE/DELETE policies.
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_events_tenant_read ON public.audit_events
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_tenant_memberships m
      WHERE m.tenant_id = public.audit_events.tenant_id
        AND m.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
        AND m.revoked_at IS NULL
    )
  );

-- Insert is service-role only (no policy needed — RLS denies INSERT by default to authenticated).

-- Hard-enforce immutability at the trigger layer. RLS alone blocks unprivileged roles but a
-- service_role / superuser context could still UPDATE/DELETE. The trigger fires for all roles.
CREATE OR REPLACE FUNCTION public.audit_events_block_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only (op=%)', TG_OP
    USING ERRCODE = 'check_violation';
END;
$$;

DROP TRIGGER IF EXISTS audit_events_no_update_delete ON public.audit_events;
CREATE TRIGGER audit_events_no_update_delete
  BEFORE UPDATE OR DELETE ON public.audit_events
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_events_block_mutation();

COMMENT ON TABLE public.audit_events
IS 'Phase 1 — append-only audit. Every state-changing op across the program writes here. Phase-4 ships query layer.';

COMMIT;
