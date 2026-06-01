-- Phase 3 — multi-rail payment sources.
-- One canonical user has N payment sources. Each source is exactly one of:
--   stripe_card / stripe_bank / bridge_virtual_account / tempo_mpp_wallet / self_custody_wallet
--
-- Phase-2 wallet credentials auto-link to a payment-source row when address matches; that
-- linking is implemented in 013_payment_credential_link.sql.
--
-- See: docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md §3.1

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_payment_sources (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  source_type    text NOT NULL CHECK (source_type IN
    ('stripe_card','stripe_bank','bridge_virtual_account','tempo_mpp_wallet','self_custody_wallet')),
  -- Stripe path (card or bank)
  stripe_payment_method_id   text,
  stripe_customer_id         text,
  -- Bridge path
  bridge_virtual_account_id  text,
  bridge_currency            text,           -- 'USD','EUR','GBP','MXN'
  -- Tempo MPP path
  tempo_wallet_id            text,
  -- Self-custody wallet path
  wallet_address             text,
  wallet_chain_id            integer,
  wallet_credential_id       uuid REFERENCES public.user_credentials(id) ON DELETE SET NULL,
  display_name   text,
  metadata       jsonb NOT NULL DEFAULT '{}'::jsonb,
  verified_at    timestamptz NOT NULL DEFAULT now(),
  disabled_at    timestamptz,
  CHECK (
    (source_type = 'stripe_card'              AND stripe_payment_method_id IS NOT NULL) OR
    (source_type = 'stripe_bank'              AND stripe_payment_method_id IS NOT NULL) OR
    (source_type = 'bridge_virtual_account'   AND bridge_virtual_account_id IS NOT NULL) OR
    (source_type = 'tempo_mpp_wallet'         AND tempo_wallet_id IS NOT NULL) OR
    (source_type = 'self_custody_wallet'      AND wallet_address IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS user_payment_sources_user_idx ON public.user_payment_sources(user_id);
CREATE INDEX IF NOT EXISTS user_payment_sources_type_idx ON public.user_payment_sources(source_type);

-- Partial uniques per rail.
CREATE UNIQUE INDEX IF NOT EXISTS user_payment_stripe_pm_uniq
  ON public.user_payment_sources(stripe_payment_method_id)
  WHERE stripe_payment_method_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_payment_bridge_va_uniq
  ON public.user_payment_sources(bridge_virtual_account_id)
  WHERE bridge_virtual_account_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_payment_tempo_uniq
  ON public.user_payment_sources(tempo_wallet_id)
  WHERE tempo_wallet_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS user_payment_wallet_uniq
  ON public.user_payment_sources(source_type, wallet_address, wallet_chain_id)
  WHERE source_type = 'self_custody_wallet';

-- Wire Phase-1's reserved primary_payment_source_id FK.
ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_primary_payment_fk
  FOREIGN KEY (primary_payment_source_id) REFERENCES public.user_payment_sources(id)
  ON DELETE SET NULL;

ALTER TABLE public.user_payment_sources ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_payment_sources_self ON public.user_payment_sources
  FOR SELECT
  USING (user_id = auth.uid());

COMMIT;
