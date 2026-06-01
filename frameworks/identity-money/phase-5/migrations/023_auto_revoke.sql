-- Phase 5.3 — Layer 2, part B: auto-revoke.
-- When an anomaly rule whose action is 'auto_revoke_scope' fires, a trigger disables
-- the offending actor's credentials, records the revocation in identity_links, AND
-- drops an actor_block as the hard stop. Reversible: an admin re-enables the
-- credentials and lifts the block.
--
-- Three real-schema constraints this migration respects:
--   1. user_credentials uses `disabled_at` (NOT the spec's `revoked_at`).
--   2. identity_links.event has a CHECK whitelist with no revocation value — extended
--      here to add 'credential_auto_revoked'.
--   3. guard_last_credential (migration 009) forbids disabling a user's LAST active
--      credential to prevent lockout. We therefore disable all-but-the-oldest and rely
--      on actor_blocks for the total stop — so auto-revoke never trips the guard.
--
-- Depends on 019 (actor_blocks). See:
-- docs/superpowers/specs/2026-05-31-phase-5-active-authorization-design.md §Layer 2

BEGIN;

-- 1. Allow the revocation event in identity_links.
ALTER TABLE public.identity_links DROP CONSTRAINT IF EXISTS identity_links_event_check;
ALTER TABLE public.identity_links ADD CONSTRAINT identity_links_event_check
  CHECK (event IN (
    'credential_linked', 'credential_unlinked', 'credential_auto_revoked',
    'kyc_initiated', 'kyc_approved', 'kyc_rejected', 'kyc_expired'
  ));

-- 2. The revoke action. Returns the number of credentials disabled. SECURITY DEFINER
-- (writes across tables regardless of caller); search_path pinned.
CREATE OR REPLACE FUNCTION public.auto_revoke_actor(
  p_actor   uuid,
  p_rule_id uuid,
  p_reason  text,
  p_block_span interval DEFAULT '24 hours'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  keep_id  uuid;
  disabled integer := 0;
  c        record;
BEGIN
  -- Keep the oldest active credential active so guard_last_credential (009) is never
  -- tripped. The actor_block below is what actually locks the actor out.
  SELECT id INTO keep_id
  FROM public.user_credentials
  WHERE user_id = p_actor AND disabled_at IS NULL
  ORDER BY verified_at ASC, id ASC
  LIMIT 1;

  FOR c IN
    SELECT id FROM public.user_credentials
    WHERE user_id = p_actor AND disabled_at IS NULL
      AND id IS DISTINCT FROM keep_id
  LOOP
    UPDATE public.user_credentials SET disabled_at = now() WHERE id = c.id;
    INSERT INTO public.identity_links (user_id, credential_id, event, performed_by, metadata)
    VALUES (p_actor, c.id, 'credential_auto_revoked', NULL,
            jsonb_build_object('rule_id', p_rule_id, 'reason', p_reason));
    disabled := disabled + 1;
  END LOOP;

  -- Hard stop regardless of how many credentials were disabled (covers the kept-last
  -- credential and actors with zero credentials). Extend any existing block.
  INSERT INTO public.actor_blocks (actor_id, blocked_until, reason, rule_id)
  VALUES (p_actor, now() + p_block_span, p_reason, p_rule_id)
  ON CONFLICT (actor_id) DO UPDATE
    SET blocked_until = GREATEST(public.actor_blocks.blocked_until, EXCLUDED.blocked_until),
        reason        = EXCLUDED.reason,
        rule_id       = EXCLUDED.rule_id,
        created_at     = now();

  RETURN disabled;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.auto_revoke_actor(uuid, uuid, text, interval) FROM PUBLIC;

COMMENT ON FUNCTION public.auto_revoke_actor(uuid, uuid, text, interval)
IS 'Phase 5.3 — disable an actor''s credentials (all but the oldest, to respect the last-credential guard), log credential_auto_revoked to identity_links, and block the actor. Reversible by an admin.';

-- 3. Trigger: fire auto-revoke for auto_revoke_scope findings. A SEPARATE trigger from
-- 019''s apply_block_next so the two enforcement paths stay independent.
CREATE OR REPLACE FUNCTION public.apply_auto_revoke()
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
  IF r.action = 'auto_revoke_scope' THEN
    PERFORM public.auto_revoke_actor(
      NEW.actor,
      r.id,
      format('anomaly rule "%s" (finding %s, measured %s)', r.name, NEW.id, NEW.measured_value),
      GREATEST(r.window_span, interval '24 hours')
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS anomaly_findings_apply_auto_revoke ON public.anomaly_findings;
CREATE TRIGGER anomaly_findings_apply_auto_revoke
  AFTER INSERT ON public.anomaly_findings
  FOR EACH ROW
  EXECUTE FUNCTION public.apply_auto_revoke();

COMMIT;
