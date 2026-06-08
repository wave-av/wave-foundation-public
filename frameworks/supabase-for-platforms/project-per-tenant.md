# Project-per-tenant (Enterprise tier)

The Enterprise path: each tenant gets their own Supabase project,
provisioned via Supabase's [Management API](https://supabase.com/docs/reference/api/v1-create-a-project).

Per ADR-001, this is opt-in (Enterprise contract). The default tier is
[schema-per-tenant](./README.md) — the schema-per-tenant pieces ship as
code; project-per-tenant is documented here and provisioned manually
until the first Enterprise customer asks.

## When to use project-per-tenant

- Customer requires physical isolation (HIPAA, gov, SOC 2 audit scope).
- Customer needs Postgres extensions WAVE doesn't enable globally.
- Customer's data volume would dominate the shared project's quota.
- Customer explicitly buys the Enterprise SLA that promises it.

## Provisioning sketch (when the first Enterprise customer lands)

```ts
// POST https://api.supabase.com/v1/projects
//
// Body:
//   {
//     "name": "wave-tenant-<tenant_id>",
//     "organization_id": "<wave-org-id>",   // WAVE's Supabase org
//     "plan": "pro",                         // never "free" for an Enterprise tenant
//     "region": "us-east-1",                 // pick per customer's data residency
//     "db_pass": "<random-strong>",          // store in Doppler wave/tenants/<id>/SUPABASE_DB_PASS
//     "kps_enabled": false                   // until needed
//   }
//
// Response: { id: <ref>, ... }
// Persist <ref> in WAVE's tenant table so the gateway/dispatcher knows where
// to send this tenant's traffic.
```

Wave needs:

- `SUPABASE_ACCESS_TOKEN` (Personal Access Token from a WAVE-operator account
  with `projects:write` scope) — in Doppler `wave/prd/SUPABASE_ACCESS_TOKEN`.
- Per-tenant outputs (project ref, JWT secret, anon key, service-role key) →
  stored under Doppler `wave/tenants/<id>/SUPABASE_*` (per ADR-002).

## What we deliberately AREN'T building until needed

- **Cross-project tenant data sync**. Schema-per-tenant uses one Postgres;
  project-per-tenant uses N. A customer that wants both is paying for both —
  no automated bridging.
- **Multi-region project picking**. Right now the only data-residency
  decision is "wherever WAVE's main project lives" — Enterprise customers can
  pick when they sign the contract.
- **Project tear-down / downgrade**. Same retention-window question as schema
  drop (see [README.md "What this framework deliberately does NOT do"]).

## See also

- [README.md](./README.md) — the schema-per-tenant default
- ADR-001 (Supabase-for-platforms) — maintained in the WAVE control plane
- Supabase Management API: <https://supabase.com/docs/reference/api/introduction>
