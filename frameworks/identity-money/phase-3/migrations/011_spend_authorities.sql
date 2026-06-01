-- Phase 3 — spend authorities.
-- Explicit cap-limited grants: "actor X may spend up to Y in window Z, drawn from source S."
-- Phase-3 scope grammar uses these to gate `pay` verbs:
--   wsc:pay:up_to_5_usd      → cap 500 cents, window 'per_request'
--   wsc:pay:up_to_500_usd    → cap 50_000 cents, window 'per_request'
--   wsc:pay:any              → no cap; requires KYC level >= 2 (see helper below)
--   tempo:pay:agent_native   → routed via tempo_mpp_wallet only
--
-- See: docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md §3.2

BEGIN;

CREATE TABLE IF NOT EXISTS public.spend_authorities (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id           uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  payment_source_id  uuid NOT NULL REFERENCES public.user_payment_sources(id) ON DELETE CASCADE,
  -- Cap in minor currency units (e.g. cents for USD).
  cap_amount         bigint,                  -- NULL ⇒ uncapped (requires KYC level >= 2)
  cap_currency       text NOT NULL DEFAULT 'USD',
  -- Window the cap applies to.
  window             text NOT NULL CHECK (window IN ('per_request','per_day','per_month','total')),
  granted_at         timestamptz NOT NULL DEFAULT now(),
  granted_by         uuid REFERENCES public.user_profiles(id),
  expires_at         timestamptz,
  revoked_at         timestamptz,
  scope_tag          text NOT NULL,            -- which scope this satisfies, e.g. 'wsc:pay:up_to_5_usd'
  metadata           jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS spend_authorities_actor_idx ON public.spend_authorities(actor_id);
CREATE INDEX IF NOT EXISTS spend_authorities_active_idx
  ON public.spend_authorities(actor_id, expires_at, revoked_at);

-- Helper for RLS / app code: does actor have an active authority for at least `amount` in window
-- `w` against payment source `src`? Active = not revoked + not expired.
CREATE OR REPLACE FUNCTION public.has_spend_authority(
  p_actor_id uuid,
  p_amount   bigint,
  p_window   text,
  p_source_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.spend_authorities a
    WHERE a.actor_id = p_actor_id
      AND a.payment_source_id = p_source_id
      AND a.window = p_window
      AND a.revoked_at IS NULL
      AND (a.expires_at IS NULL OR a.expires_at > now())
      AND (a.cap_amount IS NULL OR a.cap_amount >= p_amount)
  );
$$;

COMMENT ON FUNCTION public.has_spend_authority(uuid, bigint, text, uuid)
IS 'Phase 3 — does actor hold an active spend authority covering this amount + window + source?';

-- Uncapped helper: `wsc:pay:any` requires KYC level >= 2 (verified ID).
CREATE OR REPLACE FUNCTION public.spend_uncapped_eligible(p_actor_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT public.current_kyc_level(p_actor_id) >= 2;
$$;

ALTER TABLE public.spend_authorities ENABLE ROW LEVEL SECURITY;

CREATE POLICY spend_authorities_self ON public.spend_authorities
  FOR SELECT
  USING (actor_id = auth.uid());

COMMIT;
