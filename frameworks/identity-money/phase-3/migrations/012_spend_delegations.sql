-- Phase 3 — spend delegations.
-- Orchestrator → child agent (or human → agent) spend grants. The delegation chain is
-- read by the actor-chain helper in Phase 1, layered with a money rule:
--   Root payer = the actor at the deepest `act` claim (typically the human).
--   Orchestrator may override the root payer via explicit `pay_as` claim, which must point
--   at a user the actor holds `wsc:delegate:pay` over (encoded as a delegation row here).
--
-- See: docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md §3.3

BEGIN;

CREATE TABLE IF NOT EXISTS public.spend_delegations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grantor_id       uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  grantee_id       uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  -- Authority granted is bounded by an existing spend_authorities row.
  authority_id     uuid NOT NULL REFERENCES public.spend_authorities(id) ON DELETE CASCADE,
  -- Optional further cap (cannot exceed authority_id's cap).
  cap_amount       bigint,
  cap_currency     text NOT NULL DEFAULT 'USD',
  window           text NOT NULL CHECK (window IN ('per_request','per_day','per_month','total')),
  granted_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz,
  revoked_at       timestamptz,
  CHECK (grantor_id <> grantee_id)
);

CREATE INDEX IF NOT EXISTS spend_delegations_grantor_idx ON public.spend_delegations(grantor_id);
CREATE INDEX IF NOT EXISTS spend_delegations_grantee_idx ON public.spend_delegations(grantee_id);

-- Helper: does grantee currently hold a delegation from grantor, sufficient for amount + window?
CREATE OR REPLACE FUNCTION public.has_delegated_spend(
  p_grantor uuid,
  p_grantee uuid,
  p_amount  bigint,
  p_window  text
)
RETURNS boolean
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.spend_delegations d
    WHERE d.grantor_id = p_grantor
      AND d.grantee_id = p_grantee
      AND d.window = p_window
      AND d.revoked_at IS NULL
      AND (d.expires_at IS NULL OR d.expires_at > now())
      AND (d.cap_amount IS NULL OR d.cap_amount >= p_amount)
  );
$$;

ALTER TABLE public.spend_delegations ENABLE ROW LEVEL SECURITY;

CREATE POLICY spend_delegations_self ON public.spend_delegations
  FOR SELECT
  USING (grantor_id = auth.uid() OR grantee_id = auth.uid());

COMMIT;
