-- Phase 5.1 — anomaly rules (declarative).
-- A rule defines a pattern over public.audit_events to watch for: a LIKE-matched
-- action, an optional actor role, a time window, an aggregate, and a threshold.
-- The Phase-5.1 evaluator (migration 020) reads enabled rules and writes findings;
-- this migration ships ONLY the rule table + RLS + seed rules. No actions yet —
-- Layer 2 (auto-revoke / block_next) lands in Phase 5.3.
--
-- See: docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md §Layer 1

BEGIN;

CREATE TABLE IF NOT EXISTS public.anomaly_rules (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text NOT NULL UNIQUE,
  description      text,
  match_action     text NOT NULL,                      -- LIKE pattern over audit_events.action
  match_actor_role text,                               -- NULL = any role
  window_span      interval NOT NULL,                  -- look-back span ("window" is a reserved word)
  threshold        numeric NOT NULL CHECK (threshold > 0),
  aggregate        text NOT NULL
                     CHECK (aggregate IN ('count', 'sum_amount', 'count_distinct_resource')),
  severity         text NOT NULL
                     CHECK (severity IN ('info', 'warning', 'blocking')),
  action           text NOT NULL
                     CHECK (action IN ('alert', 'block_next', 'auto_revoke_scope')),
  enabled          boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS anomaly_rules_enabled_idx
  ON public.anomaly_rules(enabled) WHERE enabled;

COMMENT ON TABLE public.anomaly_rules
IS 'Phase 5.1 — declarative anomaly patterns over audit_events. Evaluator (020) reads enabled rules; Layer-2 actions land in Phase 5.3.';

-- RLS: writes are admin-only (any tenant owner/admin); reads are open to authenticated
-- so consumers can show the active ruleset. Rules are global (not per-tenant) — a single
-- catalog the per-tenant evaluator applies. Service-role (evaluator) bypasses RLS.
ALTER TABLE public.anomaly_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS anomaly_rules_read ON public.anomaly_rules;
CREATE POLICY anomaly_rules_read ON public.anomaly_rules
  FOR SELECT
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS anomaly_rules_admin_write ON public.anomaly_rules;
CREATE POLICY anomaly_rules_admin_write ON public.anomaly_rules
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.user_tenant_memberships m
      WHERE m.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
        AND m.revoked_at IS NULL
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_tenant_memberships m
      WHERE m.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
        AND m.revoked_at IS NULL
    )
  );

-- Seed rules. Idempotent via the UNIQUE name — re-running leaves existing rows untouched.
INSERT INTO public.anomaly_rules
  (name, description, match_action, match_actor_role, window_span, threshold, aggregate, severity, action)
VALUES
  ('hourly_spend_cap',
   'Any actor whose spend.allowed events sum to >$10k within 1 hour.',
   'spend.allowed', NULL, '1 hour', 10000, 'sum_amount', 'blocking', 'block_next'),
  ('payment_source_enumeration',
   'Same actor reading >100 distinct payment-source resources within 5 minutes.',
   'payment_source.read', NULL, '5 minutes', 100, 'count_distinct_resource', 'warning', 'alert'),
  ('admin_scope_from_non_admin',
   'A scope_used of admin:any seen on >0 events in 24h — privilege drift signal.',
   'admin.%', NULL, '24 hours', 1, 'count', 'blocking', 'auto_revoke_scope')
ON CONFLICT (name) DO NOTHING;

COMMIT;
