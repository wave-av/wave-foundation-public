-- Phase 1 — tenant model.
-- Every credential, payment source, agent, audit event carries tenant_id. user_tenant_memberships
-- is N:M between users and tenants. Adding tenancy later requires rewriting every RLS — ship now.
--
-- See: docs/superpowers/specs/2026-05-28-identity-money-program-overview.md §2.3

BEGIN;

CREATE TABLE IF NOT EXISTS public.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z][a-z0-9-]{0,62}[a-z0-9]$'),
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  disabled_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.user_tenant_memberships (
  user_id uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('owner','admin','member','guest')),
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  PRIMARY KEY (user_id, tenant_id)
);

CREATE INDEX IF NOT EXISTS utm_tenant_idx ON public.user_tenant_memberships(tenant_id);

-- Wire the deferred FK from Phase 1 migration 001: now that public.tenants exists, constrain
-- user_profiles.tenant_id so tenant-scoped data cannot drift to nonexistent tenants.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_profiles_tenant_fk'
  ) THEN
    ALTER TABLE public.user_profiles
      ADD CONSTRAINT user_profiles_tenant_fk
      FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Bootstrap tenant for the WAVE org so single-tenant consumers have a default.
INSERT INTO public.tenants (slug, display_name)
VALUES ('wave-av', 'WAVE')
ON CONFLICT (slug) DO NOTHING;

-- RLS: a user sees memberships they hold; tenant owners see all in their tenant.
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_tenant_memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_visible_to_members ON public.tenants
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.user_tenant_memberships m
      WHERE m.tenant_id = public.tenants.id
        AND m.user_id = auth.uid()
        AND m.revoked_at IS NULL
    )
  );

CREATE POLICY membership_self_visible ON public.user_tenant_memberships
  FOR SELECT
  USING (user_id = auth.uid());

-- Tenant owners/admins see every membership in their tenant (matches the visibility model
-- documented above). EXISTS-on-self is safe because the policy applies to SELECT only and is
-- short-circuited by Postgres before recursion.
CREATE POLICY membership_tenant_admin_visible ON public.user_tenant_memberships
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.user_tenant_memberships m
      WHERE m.tenant_id = public.user_tenant_memberships.tenant_id
        AND m.user_id = auth.uid()
        AND m.role IN ('owner','admin')
        AND m.revoked_at IS NULL
    )
  );

COMMIT;
