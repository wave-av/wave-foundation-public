-- Phase 2 — last-credential revocation guard.
-- Prevents the lockout failure mode: a user can never disable their last credential. Account
-- closure goes through a different code path (user_profiles.disabled_at), not through
-- credentials.
--
-- See: docs/superpowers/specs/2026-05-29-phase-2-identity-linking-design.md §4 (Failure modes)

BEGIN;

CREATE OR REPLACE FUNCTION public.guard_last_credential()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  remaining int;
BEGIN
  -- Count active credentials AFTER this disable (this row's NEW.disabled_at is non-null).
  IF NEW.disabled_at IS NOT NULL AND OLD.disabled_at IS NULL THEN
    SELECT count(*) INTO remaining
    FROM public.user_credentials
    WHERE user_id = NEW.user_id
      AND disabled_at IS NULL
      AND id <> NEW.id;
    IF remaining = 0 THEN
      RAISE EXCEPTION 'Cannot disable last active credential for user_id=% — close the account via user_profiles.disabled_at instead', NEW.user_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_credentials_revocation_guard ON public.user_credentials;
CREATE TRIGGER user_credentials_revocation_guard
  BEFORE UPDATE OF disabled_at ON public.user_credentials
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_last_credential();

-- Also prevent DELETE of last credential — same rationale.
CREATE OR REPLACE FUNCTION public.guard_last_credential_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  remaining int;
BEGIN
  SELECT count(*) INTO remaining
  FROM public.user_credentials
  WHERE user_id = OLD.user_id
    AND disabled_at IS NULL
    AND id <> OLD.id;
  IF remaining = 0 THEN
    RAISE EXCEPTION 'Cannot delete last active credential for user_id=% — close the account via user_profiles.disabled_at instead', OLD.user_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS user_credentials_delete_guard ON public.user_credentials;
CREATE TRIGGER user_credentials_delete_guard
  BEFORE DELETE ON public.user_credentials
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_last_credential_delete();

COMMIT;
