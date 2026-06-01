-- Phase 2 — dual-source KYC.
-- One canonical user has N kyc_records (one per provider). The "current verdict" is a
-- materialized projection (view) over the latest approved record per user.
--
-- Providers: stripe_identity (document + selfie liveness, US/EU best-in-class)
--            bridge          (fiat ↔ crypto on/off-ramp KYC)
-- Levels:    0 = none, 1 = email-verified, 2 = id-verified, 3 = enhanced (proof of address etc.)
--
-- Phase 3 spend_authority reads `current_kyc_level` for charge-against-rail decisions.
--
-- See: docs/superpowers/specs/2026-05-29-phase-2-identity-linking-design.md §3.2

BEGIN;

CREATE TABLE IF NOT EXISTS public.kyc_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  provider        text NOT NULL CHECK (provider IN ('stripe_identity','bridge')),
  level           smallint NOT NULL CHECK (level BETWEEN 0 AND 3),
  status          text NOT NULL CHECK (status IN ('pending','approved','rejected','expired')),
  provider_ref    text NOT NULL,            -- the provider's verification session ID
  verdict_data    jsonb NOT NULL DEFAULT '{}'::jsonb,
  evaluated_at    timestamptz,
  expires_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS kyc_records_user_provider_idx ON public.kyc_records(user_id, provider, created_at DESC);
CREATE INDEX IF NOT EXISTS kyc_records_status_idx ON public.kyc_records(status);

-- Current verdict view: latest approved record per user per provider, not yet expired.
CREATE OR REPLACE VIEW public.current_kyc AS
SELECT DISTINCT ON (user_id, provider)
  user_id,
  provider,
  level,
  status,
  evaluated_at,
  expires_at
FROM public.kyc_records
WHERE status = 'approved'
  AND (expires_at IS NULL OR expires_at > now())
ORDER BY user_id, provider, evaluated_at DESC NULLS LAST;

-- Helper used by Phase 3 spend_authority: the user's highest current KYC level across providers.
CREATE OR REPLACE FUNCTION public.current_kyc_level(p_user_id uuid)
RETURNS smallint
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT COALESCE(MAX(level), 0)::smallint
  FROM public.current_kyc
  WHERE user_id = p_user_id;
$$;

ALTER TABLE public.kyc_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY kyc_records_self ON public.kyc_records
  FOR SELECT
  USING (user_id = auth.uid());

COMMIT;
