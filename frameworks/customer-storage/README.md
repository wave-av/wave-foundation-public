# `frameworks/customer-storage/` — tenant→bucket routing for the 10-R2-pool pattern

Operationalizes ADR-004 from the WAVE control plane: customer storage
is sharded across `wave-customer-storage-pool-{0..9}` by
`SHA-256(tenant_id) % 10`. Every signed-URL minter in every spoke MUST
call `bucketForTenant()` — never inline the bucket-name string.

## Why a foundation framework

The pool size, prefix, and hash function are part of the contract
between control-plane (which provisions buckets) and data-plane (which
mints signed URLs). If a spoke computes the bucket differently than the
control plane wrote the object to, every read returns 404. One source
of truth, vendored everywhere.

## Contents

| File | Purpose |
|---|---|
| `README.md` | This file. |
| `bucket-for-tenant.ts` | Canonical TypeScript helper (CF Workers + Node 20+). Mirrors the control-plane `storage.ts`. |
| `bucket_for_tenant.py` | Canonical Python helper (3.11+). For Supabase Edge Functions / scripts. |
| `tests/` | Cross-implementation tests asserting TS and Python return identical buckets for the same tenant_id. |

## Wiring

Spokes vendor this directory via `consume.sh` (it's part of
`frameworks/`). After running, `.foundation/frameworks/customer-storage/`
appears in the spoke; import directly from there.

## Contract

- `bucketForTenant(tenant_id: string): Promise<string>` (TS) or
  `bucket_for_tenant(tenant_id: str) -> str` (Python).
- Returns `wave-customer-storage-pool-{0..9}` always.
- Deterministic. Same `tenant_id` → same bucket forever (immutable).
- Pool expansion: when buckets 10+ are added, EXISTING tenants stay on
  mod-10. New tenants signed up after the switch use the new modulus,
  set via `WAVE_STORAGE_POOL_SIZE` env var. Both implementations honour
  this env var.

## See also

- ADR-004 (storage-pool routing) — maintained in the WAVE control plane
