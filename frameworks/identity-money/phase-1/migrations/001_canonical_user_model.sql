-- Phase 1 — canonical user model.
-- Adds public.user_profiles (1:1 with auth.users). Multi-tenant from day one; per-category
-- (human/agent/bot/orchestrator/integration). FK columns to credentials/payment-source are
-- nullable now and constrained in Phases 2/3 (avoids painful populated-table migrations).
--
-- See: docs/superpowers/specs/2026-05-28-identity-money-program-overview.md §2.1

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL,
  category text NOT NULL CHECK (category IN ('human','agent','bot','orchestrator','integration')),
  display_name text,
  created_at timestamptz NOT NULL DEFAULT now(),
  disabled_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  kyc_status jsonb,                          -- Phase 2 populates
  primary_credential_id uuid,                -- Phase 2 adds FK
  primary_payment_source_id uuid             -- Phase 3 adds FK
);

CREATE INDEX IF NOT EXISTS user_profiles_tenant_idx ON public.user_profiles(tenant_id);
CREATE INDEX IF NOT EXISTS user_profiles_category_idx ON public.user_profiles(category);

-- RLS: a user sees their own profile; tenant admins see all in tenant; service-role bypasses.
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_profiles_self_read ON public.user_profiles
  FOR SELECT
  USING (id = auth.uid());

CREATE POLICY user_profiles_self_update ON public.user_profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND tenant_id = (SELECT tenant_id FROM public.user_profiles WHERE id = auth.uid()));

COMMIT;
