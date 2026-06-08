# `frameworks/doppler-tenant-namespace/` — per-tenant secrets at `wave/tenants/{id}/`

Operationalizes ADR-002 from the WAVE control plane: tenant secrets
live in Doppler under the `wave/tenants` config with `{tenant_id}/`
key-prefixes (Doppler doesn't nest configs natively).

## What you get

| File | Purpose |
|---|---|
| `README.md` | This file. |
| `tenant-secrets.ts` | Canonical TS API: `secretsFor(tenantId)` + `setSecret(tenantId, name, value)`. Mirrors the control-plane `secrets.ts`. |

A Python counterpart (`tenant_secrets.py`) is intentionally NOT shipped yet —
the only current caller is the WAVE control plane (TypeScript). File a
follow-up when a Python caller actually exists; the TS shape is the
contract.

## Contract

- Names are SCREAMING_SNAKE_CASE (`^[A-Z][A-Z0-9_]{0,63}$`).
- Tenant ids are slug-safe (`^[a-zA-Z0-9_-]{1,64}$`).
- Reads pull from `wave/tenants/{tenant_id}/*` and strip the prefix.
- Writes prepend `{tenant_id}/` automatically — callers cannot escape into
  another tenant's namespace.
- The Doppler token MUST be a tenant-scoped service-account token
  (one per tenant or per-cohort, rotated by WAVE control plane). NEVER
  a global `wave/*` token — that would defeat per-tenant blast-radius.

## Wiring

Spokes vendor this directory via `consume.sh` (frameworks/ is already
in `VENDOR_DIRS`). All Doppler reads/writes from spoke code MUST go
through these helpers; direct Doppler API calls are a contract
violation. A future foundation CI gate should flag direct calls.

## See also

- ADR-002 (Doppler tenant namespace) — maintained in the WAVE control plane
- [`frameworks/supabase-for-platforms/`](../supabase-for-platforms/) — paired pattern: tenant Doppler secrets feed tenant Supabase JWTs
- [`frameworks/customer-storage/`](../customer-storage/) — paired pattern: tenant R2 bucket routing
