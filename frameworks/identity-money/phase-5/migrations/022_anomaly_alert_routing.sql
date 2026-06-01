-- Phase 5.2 — Layer 3 alert routing state.
-- Adds the bookkeeping a consumer-side poller needs to route each finding to its
-- sinks (per frameworks/observability/anomaly-routes.yml) exactly once:
--   - alerted_at  : set when the finding has been dispatched to its sinks
--   - a view of findings still awaiting routing (unresolved AND not yet alerted)
--   - mark_anomaly_alerted(finding_id) : the poller calls this after a successful route
--
-- No external calls happen in Postgres — alerting is a consumer concern (it needs the
-- spoke's Sentry/Linear/Slack secrets). This migration only tracks routing state.
--
-- See: docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md §Layer 3

BEGIN;

ALTER TABLE public.anomaly_findings
  ADD COLUMN IF NOT EXISTS alerted_at timestamptz;

-- Findings the poller still owes an alert: unresolved, not yet alerted, severity above
-- info (info is logged, never alerted — see anomaly-routes.yml). Joined to the rule so
-- the poller has rule_name + action without a second query.
CREATE OR REPLACE VIEW public.anomaly_findings_to_alert AS
  SELECT
    f.id            AS finding_id,
    f.rule_id,
    r.name          AS rule_name,
    r.action        AS rule_action,
    f.severity,
    f.tenant_id,
    f.actor,
    f.measured_value,
    r.threshold,
    f.window_start,
    f.window_end,
    f.ts
  FROM public.anomaly_findings f
  JOIN public.anomaly_rules r ON r.id = f.rule_id
  WHERE f.resolved_at IS NULL
    AND f.alerted_at IS NULL
    AND f.severity IN ('warning', 'blocking')
  ORDER BY f.ts DESC;

COMMENT ON VIEW public.anomaly_findings_to_alert
IS 'Phase 5.2 — findings awaiting Layer-3 routing (unresolved, un-alerted, severity>info). Poller reads this, routes per anomaly-routes.yml, then calls mark_anomaly_alerted().';

-- The poller marks a finding alerted after it has dispatched to the sinks. SECURITY
-- INVOKER: it runs as the poller's role and only flips alerted_at — the RLS UPDATE
-- policy (anomaly_findings_tenant_resolve) still governs who may call it on which row.
CREATE OR REPLACE FUNCTION public.mark_anomaly_alerted(finding_id uuid)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
AS $$
  UPDATE public.anomaly_findings
     SET alerted_at = now()
   WHERE id = finding_id
     AND alerted_at IS NULL;
$$;

COMMENT ON FUNCTION public.mark_anomaly_alerted(uuid)
IS 'Phase 5.2 — idempotently stamp alerted_at after a finding is routed to its sinks. No-op if already alerted.';

COMMIT;
