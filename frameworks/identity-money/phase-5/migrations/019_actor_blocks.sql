-- Phase 5.3 — Layer 2, part A: actor blocks.
-- The "block_next" enforcement primitive. When an anomaly rule whose action is
-- 'block_next' fires, a trigger drops the offending actor into public.actor_blocks
-- with a TTL. The authorization gate auth.actor_can() then refuses the actor's next
-- request until the block expires.
--
-- Design note: we DO NOT modify the existing auth.has_scope(text[], text). It is
-- IMMUTABLE/PARALLEL SAFE and called by every RLS policy in the program — adding a
-- table read would break that contract. Instead this adds a STABLE gate, auth.actor_can(),
-- that composes has_scope with a block check. Callers that want block enforcement use
-- actor_can(); pure scope checks keep using has_scope().
--
-- See: docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md §Layer 2

BEGIN;

CREATE TABLE IF NOT EXISTS public.actor_blocks (
  actor_id      uuid PRIMARY KEY,                    -- one active block per actor
  blocked_until timestamptz NOT NULL,
  reason        text NOT NULL,
  rule_id       uuid REFERENCES public.anomaly_rules(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS actor_blocks_active_idx
  ON public.actor_blocks(actor_id, blocked_until);

COMMENT ON TABLE public.actor_blocks
IS 'Phase 5.3 — active actor blocks (block_next). auth.actor_can() refuses a blocked actor until blocked_until passes. One row per actor; re-firing extends the TTL.';

-- O(1) block check. STABLE (reads a table + now()), so it is NOT a drop-in for the
-- IMMUTABLE has_scope — it is composed by actor_can() below.
CREATE OR REPLACE FUNCTION auth.is_actor_blocked(actor_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.actor_blocks b
    WHERE b.actor_id = $1 AND b.blocked_until > now()
  );
$$;

COMMENT ON FUNCTION auth.is_actor_blocked(uuid)
IS 'Phase 5.3 — true while the actor has an unexpired block. O(1) via actor_blocks_active_idx.';

-- The block-aware authorization gate: hold the scope AND not be blocked. Callers that
-- need block enforcement use this in place of bare has_scope().
CREATE OR REPLACE FUNCTION auth.actor_can(actor_id uuid, claim_scopes text[], required text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT auth.has_scope(claim_scopes, required) AND NOT auth.is_actor_blocked(actor_id);
$$;

COMMENT ON FUNCTION auth.actor_can(uuid, text[], text)
IS 'Phase 5.3 — block-aware scope gate: has_scope(scopes, required) AND NOT is_actor_blocked(actor). Use instead of has_scope() on paths that must honor anomaly blocks.';

-- Trigger: when a finding lands for a block_next rule, block the actor for the rule''s
-- window_span. SECURITY DEFINER (writes actor_blocks regardless of caller role); search_path
-- pinned. Aggregate findings (actor IS NULL) are skipped — nothing specific to block.
CREATE OR REPLACE FUNCTION public.apply_block_next()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r public.anomaly_rules%ROWTYPE;
BEGIN
  IF NEW.actor IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO r FROM public.anomaly_rules WHERE id = NEW.rule_id;
  IF r.action = 'block_next' THEN
    INSERT INTO public.actor_blocks (actor_id, blocked_until, reason, rule_id)
    VALUES (
      NEW.actor,
      now() + r.window_span,
      format('anomaly rule "%s" (finding %s, measured %s)', r.name, NEW.id, NEW.measured_value),
      r.id
    )
    ON CONFLICT (actor_id) DO UPDATE
      SET blocked_until = GREATEST(public.actor_blocks.blocked_until, EXCLUDED.blocked_until),
          reason        = EXCLUDED.reason,
          rule_id       = EXCLUDED.rule_id,
          created_at     = now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS anomaly_findings_apply_block ON public.anomaly_findings;
CREATE TRIGGER anomaly_findings_apply_block
  AFTER INSERT ON public.anomaly_findings
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_block_next();

-- RLS: blocks are cross-tenant enforcement records. Read + manage (lift a block) for any
-- tenant owner/admin; the trigger writes as SECURITY DEFINER so it bypasses RLS.
ALTER TABLE public.actor_blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS actor_blocks_admin_all ON public.actor_blocks;
CREATE POLICY actor_blocks_admin_all ON public.actor_blocks
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

COMMIT;
