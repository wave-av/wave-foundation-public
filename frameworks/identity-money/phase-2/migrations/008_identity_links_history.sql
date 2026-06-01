-- Phase 2 — append-only identity-link history.
-- Every link/unlink event is recorded. The current-state view projects from this history.
-- Required for the Phase 4 unified audit: "when did this user first link wallet X?"
--
-- See: docs/superpowers/specs/2026-05-29-phase-2-identity-linking-design.md §3.3

BEGIN;

CREATE TABLE IF NOT EXISTS public.identity_links (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  credential_id  uuid REFERENCES public.user_credentials(id) ON DELETE SET NULL,
  kyc_id         uuid REFERENCES public.kyc_records(id) ON DELETE SET NULL,
  event          text NOT NULL CHECK (event IN
    ('credential_linked','credential_unlinked','kyc_initiated','kyc_approved','kyc_rejected','kyc_expired')),
  performed_by   uuid REFERENCES public.user_profiles(id),  -- self-service vs admin
  ts             timestamptz NOT NULL DEFAULT now(),
  metadata       jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (
    (event LIKE 'credential_%' AND credential_id IS NOT NULL) OR
    (event LIKE 'kyc_%'        AND kyc_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS identity_links_user_ts_idx ON public.identity_links(user_id, ts DESC);
CREATE INDEX IF NOT EXISTS identity_links_event_idx ON public.identity_links(event);

-- identity_links is append-only. No UPDATE/DELETE policy.
ALTER TABLE public.identity_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY identity_links_self ON public.identity_links
  FOR SELECT
  USING (user_id = auth.uid());

COMMIT;
