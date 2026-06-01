-- Phase 5.1 — anomaly findings.
-- The evaluator (migration 020) inserts one row here each time an enabled rule fires.
-- Layer 3 (alerting, Phase 5.2) reads unresolved rows and routes them to Sentry /
-- Linear / Slack; Layer 2 (Phase 5.3) reads the rule.action to decide block/revoke.
-- Findings are tenant-scoped: a rule is global but every firing is attributed to the
-- tenant whose audit_events tripped it.
--
-- See: docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md §Layer 1

BEGIN;

CREATE TABLE IF NOT EXISTS public.anomaly_findings (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id         uuid NOT NULL REFERENCES public.anomaly_rules(id) ON DELETE RESTRICT,
  ts              timestamptz NOT NULL DEFAULT now(),
  -- Findings are always attributed to a tenant. ON DELETE RESTRICT keeps the forensic
  -- trail intact — a finding must never become an orphan, same posture as audit_events.
  tenant_id       uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  actor           uuid,                         -- leaf actor that tripped the rule (NULL = aggregate)
  measured_value  numeric NOT NULL,             -- the aggregate value that crossed the threshold
  window_start    timestamptz NOT NULL,
  window_end      timestamptz NOT NULL,
  evidence        jsonb,                        -- sample of the audit_events rows that triggered
  resolved_at     timestamptz,
  resolution_note text,
  CHECK (window_end >= window_start)
);

-- Denormalize severity onto the finding for the alerting partial index (Layer 3 queries
-- "unresolved findings at/above warning" without joining anomaly_rules on the hot path).
ALTER TABLE public.anomaly_findings
  ADD COLUMN IF NOT EXISTS severity text
    CHECK (severity IN ('info', 'warning', 'blocking'));

CREATE INDEX IF NOT EXISTS anomaly_findings_unresolved_idx
  ON public.anomaly_findings(severity, ts DESC) WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS anomaly_findings_tenant_ts_idx
  ON public.anomaly_findings(tenant_id, ts DESC);

CREATE INDEX IF NOT EXISTS anomaly_findings_rule_idx
  ON public.anomaly_findings(rule_id);

COMMENT ON TABLE public.anomaly_findings
IS 'Phase 5.1 — a row per rule firing. Layer-3 alerting reads unresolved rows; Layer-2 actions key off the rule.action.';

-- RLS: per-tenant read for owner/admin (mirrors audit_events_tenant_read). Inserts are
-- service-role only (the evaluator); UPDATE is allowed for owner/admin to set resolved_at
-- + resolution_note (triage), but never to rewrite the finding facts.
ALTER TABLE public.anomaly_findings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS anomaly_findings_tenant_read ON public.anomaly_findings;
CREATE POLICY anomaly_findings_tenant_read ON public.anomaly_findings
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_tenant_memberships m
      WHERE m.tenant_id = public.anomaly_findings.tenant_id
        AND m.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
        AND m.revoked_at IS NULL
    )
  );

DROP POLICY IF EXISTS anomaly_findings_tenant_resolve ON public.anomaly_findings;
CREATE POLICY anomaly_findings_tenant_resolve ON public.anomaly_findings
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.user_tenant_memberships m
      WHERE m.tenant_id = public.anomaly_findings.tenant_id
        AND m.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
        AND m.revoked_at IS NULL
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.user_tenant_memberships m
      WHERE m.tenant_id = public.anomaly_findings.tenant_id
        AND m.user_id = auth.uid()
        AND m.role IN ('owner', 'admin')
        AND m.revoked_at IS NULL
    )
  );

COMMIT;
