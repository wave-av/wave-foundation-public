-- Phase 3 — auto-link Phase-2 wallet credentials to Phase-3 self_custody_wallet payment sources.
-- Same-address wallet (Phase 2) + same-address payment source (Phase 3) belong to the same user;
-- the link reads from credentials → payment_sources via wallet_credential_id.
--
-- This trigger fires on INSERT into user_payment_sources where source_type = self_custody_wallet:
--   1. find the matching wallet credential for (user_id, kind LIKE 'wallet_%', wallet_address, chain_id)
--   2. if found, populate wallet_credential_id on the new payment_sources row
--
-- See: docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md §3.4

BEGIN;

CREATE OR REPLACE FUNCTION public.link_wallet_credential_to_payment_source()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  matching_cred_id uuid;
BEGIN
  IF NEW.source_type <> 'self_custody_wallet' OR NEW.wallet_address IS NULL THEN
    RETURN NEW;
  END IF;
  -- Find the Phase-2 credential row for this user + address + chain (if chain matters)
  SELECT id INTO matching_cred_id
  FROM public.user_credentials
  WHERE user_id = NEW.user_id
    AND kind LIKE 'wallet_%'
    AND wallet_address = NEW.wallet_address
    AND (NEW.wallet_chain_id IS NULL OR wallet_chain_id = NEW.wallet_chain_id)
    AND disabled_at IS NULL
  ORDER BY verified_at DESC
  LIMIT 1;
  IF matching_cred_id IS NOT NULL THEN
    NEW.wallet_credential_id := matching_cred_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS payment_source_link_wallet ON public.user_payment_sources;
CREATE TRIGGER payment_source_link_wallet
  BEFORE INSERT ON public.user_payment_sources
  FOR EACH ROW
  EXECUTE FUNCTION public.link_wallet_credential_to_payment_source();

COMMENT ON FUNCTION public.link_wallet_credential_to_payment_source()
IS 'Phase 3 — auto-link Phase-2 wallet credential row to a new self_custody_wallet payment source by address match.';

COMMIT;
