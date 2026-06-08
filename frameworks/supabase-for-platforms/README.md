# `frameworks/supabase-for-platforms/` — per-tenant schemas with RLS

Operationalizes ADR-001 from the WAVE control plane: schema-per-tenant in
WAVE's shared Supabase project is the default; project-per-tenant via
Supabase's Management API is the Enterprise tier.

This framework ships the schema-per-tenant pieces (the path 99% of
customers take). Project-per-tenant is a separate adoption — covered
in [`project-per-tenant.md`](./project-per-tenant.md).

## What you get

| File | Purpose |
|---|---|
| `README.md` | This file. |
| `tenant-schema-template.sql` | Idempotent SQL to provision one tenant: schema, audit columns, RLS template, `tenant_id` claim grant. Run with `psql -v tenant_id='abc'` or via `provision-tenant.ts`. |
| `provision-tenant.ts` | TS helper for the WAVE control plane. Reads the SQL template + binds `:'tenant_id'`. Idempotent — safe to re-run. |
| `tenant-jwt.ts` | Issues a tenant-scoped Supabase JWT with `tenant_id` claim baked in. Tenant scripts read their own schema with this. |
| `tests/test_jwt.py` | Parity tests: TS and Py issuers produce JWTs Supabase RLS accepts. |
| `project-per-tenant.md` | Documentation of the Enterprise path (Management API + per-tenant project provisioning). No code today — provisioned manually until the first Enterprise customer asks. |

## The RLS pattern (canonical)

Every tenant table has a `tenant_id text` column and a single RLS policy:

```sql
CREATE POLICY tenant_isolation ON tenant_abc.<table>
  FOR ALL
  USING (tenant_id = (current_setting('request.jwt.claims', true)::json ->> 'tenant_id'))
  WITH CHECK (tenant_id = (current_setting('request.jwt.claims', true)::json ->> 'tenant_id'));
```

- `USING` clause filters SELECT/UPDATE/DELETE.
- `WITH CHECK` clause forces INSERTs to bind to the caller's tenant_id
  (prevents a SQL-injection-style tenant escape).
- The `request.jwt.claims` setting is what Supabase sets per-request from
  the incoming JWT — see [`tenant-jwt.ts`](./tenant-jwt.ts) for the
  claim shape.

Every NEW tenant table must include this policy — enforced via a CI
gate that scans for `CREATE TABLE` in tenant schemas without a matching
`CREATE POLICY tenant_isolation`. (TODO: write the gate.)

## Wiring

Spokes vendor this directory via `consume.sh` (it's part of `frameworks/`).
After running, `.foundation/frameworks/supabase-for-platforms/` appears in
the spoke.

The control plane calls `provision-tenant.ts`
when a new tenant signs up. Tenant scripts on CFWFP call `tenant-jwt.ts`
to obtain a tenant-scoped JWT for their per-request Supabase queries.

## What this framework deliberately does NOT do

- **Migrate per-tenant data.** Tenants don't move between schemas — see ADR-004
  storage-pool routing for the same principle on R2.
- **Cross-tenant joins.** RLS forbids them by design. If you need
  cross-tenant aggregation, that's the platform-owned `public` schema's
  job (with separate RLS / service-role access patterns).
- **Tenant deletion (yet).** `DROP SCHEMA tenant_<id> CASCADE` is the
  obvious one-liner, but it needs a "soft-delete with retention window"
  policy first. File a follow-up when first tenant churns.

## See also

- ADR-001 (Supabase-for-platforms) — maintained in the WAVE control plane
- [`frameworks/customer-storage/`](../customer-storage/) — sibling pattern for R2 storage
- [`rules/supabase-prod-guard.md`](../../rules/supabase-prod-guard.md) — prod is READ-ONLY for agents; provision via staging first
