# Privy Per-Tenant App

Per-tenant Privy app wrapper. Each tenant gets a dedicated Privy app (created in the Privy
dashboard, not API-provisionable as of 2026-06). The wrapper:

1. **Verifies app readiness** on signup via `provisionTenantPrivyApp()`
2. **Scopes every server-API call** to `(app_id, app_secret)` via `TenantPrivyClient`

## Pattern

```ts
provisionTenantPrivyApp(input) -> { app_id, app_secret_fingerprint, login_methods }
new TenantPrivyClient(tenantId, appId, appSecret) -> { getUser, verifyAccessToken }
```

## Usage

```ts
import {
  provisionTenantPrivyApp,
  TenantPrivyClient,
} from "@wave-av/foundation/frameworks/privy-tenant-app";

// 1) On signup (or rotation): verify the Privy app the tenant created is reachable.
const ready = await provisionTenantPrivyApp({
  tenant_id: "acme",
  app_id: tenant.privy_app_id,
  app_secret: tenant.privy_app_secret,  // from Doppler tenant-namespace
});
// Persist ready.login_methods + ready.app_secret_fingerprint for audit.

// 2) Per-request: verify the access token a tenant user presented.
const privy = new TenantPrivyClient(
  "acme",
  tenant.privy_app_id,
  tenant.privy_app_secret,
);
const user = await privy.verifyAccessToken(accessToken);
// user.user_id is now safe to attribute to tenant "acme".
```

## Security

- `tenant_id` + `app_id` + `user_id` all shape-validated before use in URL paths.
- Basic-auth is bound to `(app_id, app_secret)` at client construction time — a session
  token issued for tenant A's app **cannot** authenticate against tenant B's app even if
  the token leaks, because tenant B's client uses tenant B's basic-auth.
- `app_secret` is never logged. Only the SHA-256 fingerprint is persisted for audit.
- `app_secret` length validated ≥30 chars (Privy emits >30) — catches accidental empty pass-through.

## Test plan

```bash
npx vitest run frameworks/privy-tenant-app
```

## Refs

- Task #201
- Paired with `doppler-tenant-namespace` (where app_secret is stored)
- Anti-spoof reference: ADR-009 multi-tenant token isolation
