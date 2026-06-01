-- Phase 5.1 — anomaly rule evaluator.
-- The plpgsql function pg_cron calls (migration 021). Loops over every enabled rule,
-- aggregates matching audit_events inside the rule's window, groups by (tenant, leaf
-- actor), and inserts a finding wherever the aggregate crosses the threshold.
--
-- Idempotent within a window: a (rule, tenant, actor) that already has a finding whose
-- window still overlaps "now" is skipped, so re-running every 60s does not double-fire.
-- No enforcement here — findings are inert until Phase 5.2 (alerting) / 5.3 (actions).
--
-- See: docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md §Worker flow

BEGIN;

-- SECURITY DEFINER: the evaluator reads audit_events across all tenants and writes
-- findings — it runs as a privileged scheduled job, not an end user. search_path is
-- pinned so a malicious object on a caller's path can't be resolved. EXECUTE is
-- revoked from PUBLIC; only the job role (or service_role) calls it.
CREATE OR REPLACE FUNCTION public.evaluate_anomaly_rules()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r          public.anomaly_rules%ROWTYPE;
  win_start  timestamptz;
  win_end    timestamptz := now();
  this_count integer;
  inserted   integer := 0;
BEGIN
  FOR r IN SELECT * FROM public.anomaly_rules WHERE enabled LOOP
    win_start := win_end - r.window_span;

    WITH matched AS (
      SELECT
        ae.tenant_id,
        ae.actor_chain[cardinality(ae.actor_chain)] AS actor,  -- leaf = acting principal
        ae.resource,
        ae.action,
        (ae.after ->> 'amount')::numeric AS amount,
        ae.event_id,
        ae.ts,
        row_number() OVER (
          PARTITION BY ae.tenant_id, ae.actor_chain[cardinality(ae.actor_chain)]
          ORDER BY ae.ts DESC
        ) AS rn
      FROM public.audit_events ae
      WHERE ae.action LIKE r.match_action
        AND ae.ts >= win_start
        AND ae.ts <= win_end
        AND (
          r.match_actor_role IS NULL
          OR EXISTS (
            SELECT 1 FROM public.user_tenant_memberships m
            WHERE m.user_id = ae.actor_chain[cardinality(ae.actor_chain)]
              AND m.tenant_id = ae.tenant_id
              AND m.role = r.match_actor_role
              AND m.revoked_at IS NULL
          )
        )
    ),
    agg AS (
      SELECT
        tenant_id,
        actor,
        CASE r.aggregate
          WHEN 'count'                   THEN count(*)::numeric
          WHEN 'sum_amount'              THEN coalesce(sum(amount), 0)
          WHEN 'count_distinct_resource' THEN count(DISTINCT resource)::numeric
        END AS measured,
        jsonb_agg(
          jsonb_build_object('event_id', event_id, 'action', action, 'resource', resource, 'ts', ts)
          ORDER BY ts DESC
        ) FILTER (WHERE rn <= 10) AS sample   -- cap the evidence at 10 rows
      FROM matched
      GROUP BY tenant_id, actor
    )
    INSERT INTO public.anomaly_findings
      (rule_id, tenant_id, actor, measured_value, window_start, window_end, evidence, severity)
    SELECT
      r.id, a.tenant_id, a.actor, a.measured, win_start, win_end,
      jsonb_build_object(
        'rule', r.name,
        'aggregate', r.aggregate,
        'threshold', r.threshold,
        'sample', a.sample
      ),
      r.severity
    FROM agg a
    WHERE a.measured >= r.threshold
      AND NOT EXISTS (
        SELECT 1 FROM public.anomaly_findings f
        WHERE f.rule_id = r.id
          AND f.actor IS NOT DISTINCT FROM a.actor
          AND f.tenant_id = a.tenant_id
          AND f.window_end > win_end - r.window_span   -- an overlapping finding already covers this
      );

    GET DIAGNOSTICS this_count = ROW_COUNT;
    inserted := inserted + this_count;
  END LOOP;

  RETURN inserted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.evaluate_anomaly_rules() FROM PUBLIC;

COMMENT ON FUNCTION public.evaluate_anomaly_rules()
IS 'Phase 5.1 — evaluates every enabled anomaly_rule against audit_events, inserts findings over threshold. Returns count inserted. Idempotent within a window. Called by pg_cron (021).';

COMMIT;
