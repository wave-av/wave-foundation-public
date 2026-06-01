-- Phase 2 — multi-credential linking.
-- A canonical user_profile has N credentials. Each credential is exactly one of:
--   passkey  (WebAuthn) | wallet_evm | wallet_sol | oidc_external
--
-- Per identity-policy.md rule 7: one canonical user, N credentials. Last-credential revocation
-- is guarded by a trigger shipped in migration 009 (prevents lockout).
--
-- Compatibility: extends the Phase-1 schema (public.user_profiles). Phase 1 reserved the
-- public.user_profiles.primary_credential_id column nullable for this purpose; the FK is added
-- here without migrating populated rows.
--
-- See: docs/superpowers/specs/2026-05-29-phase-2-identity-linking-design.md §3.1

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_credentials (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  kind            text NOT NULL CHECK (kind IN ('passkey','wallet_evm','wallet_sol','oidc_external')),
  -- Passkey path: opaque external identifier (Supabase Auth handles the WebAuthn details)
  webauthn_external_id text,
  -- Wallet path: EIP-55 checksummed EVM address or base58 Solana
  wallet_address  text,
  wallet_chain_id integer,
  -- Federated OIDC path
  oidc_issuer     text,
  oidc_subject    text,
  -- Common
  display_name    text,
  verified_at     timestamptz NOT NULL DEFAULT now(),
  last_used_at    timestamptz,
  disabled_at     timestamptz,
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (
    (kind = 'passkey'         AND webauthn_external_id IS NOT NULL) OR
    (kind LIKE 'wallet_%'     AND wallet_address IS NOT NULL) OR
    (kind = 'oidc_external'   AND oidc_issuer IS NOT NULL AND oidc_subject IS NOT NULL)
  )
);

-- Uniqueness per credential family — partial unique indexes (Postgres syntax)
CREATE UNIQUE INDEX IF NOT EXISTS user_credentials_wallet_uniq
  ON public.user_credentials(kind, wallet_address)
  WHERE kind LIKE 'wallet_%';

CREATE UNIQUE INDEX IF NOT EXISTS user_credentials_oidc_uniq
  ON public.user_credentials(kind, oidc_issuer, oidc_subject)
  WHERE kind = 'oidc_external';

CREATE INDEX IF NOT EXISTS user_credentials_user_idx ON public.user_credentials(user_id);

-- Wire Phase-1's reserved column to its real FK now.
ALTER TABLE public.user_profiles
  ADD CONSTRAINT user_profiles_primary_credential_fk
  FOREIGN KEY (primary_credential_id) REFERENCES public.user_credentials(id)
  ON DELETE SET NULL;

ALTER TABLE public.user_credentials ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_credentials_self ON public.user_credentials
  FOR SELECT
  USING (user_id = auth.uid());

COMMIT;
