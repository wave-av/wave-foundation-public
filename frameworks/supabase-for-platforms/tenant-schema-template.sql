-- tenant-schema-template.sql
--
-- Idempotent provisioning for one tenant under the schema-per-tenant pattern
-- (ADR-001 in the WAVE control plane). Invoke with:
--
--   psql "$DB_URL" -v tenant_id='abc' -f tenant-schema-template.sql
--
-- ...or via the TS wrapper `provision-tenant.ts` (which binds :'tenant_id'
-- safely against SQL injection — the psql -v form trusts the caller).
--
-- After running, the tenant has:
--   - A schema named tenant_<id>
--   - audit_columns(created_at, updated_at) on all tables (function ensures it)
--   - A "knowledge" reference table demonstrating the RLS pattern
--   - The tenant_isolation policy on that table
--   - Grants for authenticated + anon roles (Supabase Data API exposure)
--
-- Re-runnable: every CREATE uses IF NOT EXISTS or CREATE OR REPLACE.
-- Drop is NOT included here — see README.md "What this framework deliberately
-- does NOT do".

\set ON_ERROR_STOP on

-- 1. Schema (one per tenant). Name format: tenant_<id> (slug-safe IDs only).
CREATE SCHEMA IF NOT EXISTS tenant_:tenant_id;

-- 2. Helper: a trigger function that maintains updated_at on every row touch.
--    Lives in public so all tenant schemas can reference it.
CREATE OR REPLACE FUNCTION public.set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- 3. Reference table: demonstrates the pattern. Real tenant tables follow this
--    shape. The `tenant_id text NOT NULL` column is REQUIRED on every tenant
--    table for the RLS predicate to work.
CREATE TABLE IF NOT EXISTS tenant_:tenant_id.knowledge (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   text NOT NULL,                          -- bound by RLS to JWT claim
  title       text NOT NULL,
  body        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 4. Default the tenant_id on insert (saves callers from passing it every time;
--    RLS WITH CHECK still verifies it matches the JWT claim, so this is just
--    ergonomic, not a security shortcut).
ALTER TABLE tenant_:tenant_id.knowledge
  ALTER COLUMN tenant_id SET DEFAULT :'tenant_id';

-- 5. updated_at trigger.
DROP TRIGGER IF EXISTS set_knowledge_updated_at ON tenant_:tenant_id.knowledge;
CREATE TRIGGER set_knowledge_updated_at
  BEFORE UPDATE ON tenant_:tenant_id.knowledge
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 6. Enable RLS. Tables in exposed schemas without RLS are open by default;
--    this is the load-bearing line — DO NOT remove or skip.
ALTER TABLE tenant_:tenant_id.knowledge ENABLE ROW LEVEL SECURITY;

-- 7. The canonical tenant_isolation policy. Every NEW tenant table must add
--    one shaped like this (CI gate enforces — see README).
DROP POLICY IF EXISTS tenant_isolation ON tenant_:tenant_id.knowledge;
CREATE POLICY tenant_isolation ON tenant_:tenant_id.knowledge
  FOR ALL TO authenticated
  USING      (tenant_id = (current_setting('request.jwt.claims', true)::json ->> 'tenant_id'))
  WITH CHECK (tenant_id = (current_setting('request.jwt.claims', true)::json ->> 'tenant_id'));

-- 8. Grants for the Data API. The tenant's signed-JWT carries the
--    authenticated role; without USAGE on the schema, the tenant gets a
--    "schema not exposed" 401. anon role is NOT granted (this schema is
--    authenticated-only).
GRANT USAGE ON SCHEMA tenant_:tenant_id TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON ALL TABLES IN SCHEMA tenant_:tenant_id TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA tenant_:tenant_id
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

-- 9. Verification: at least one policy on at least one table in the schema.
DO $$
DECLARE
  policy_count int;
BEGIN
  SELECT count(*) INTO policy_count
  FROM pg_policies
  WHERE schemaname = 'tenant_' || :'tenant_id';
  IF policy_count = 0 THEN
    RAISE EXCEPTION 'tenant_isolation policy missing on tenant_%', :'tenant_id';
  END IF;
END $$;
