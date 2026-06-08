# CF Custom Hostname Per-Tenant

Per-tenant Cloudflare Custom Hostname (SSL-for-SaaS). Tenants point their own `app.acme.com`
at WAVE; CF provisions a TLS cert and binds the hostname into our zone so traffic routes to
a tenant-specific Worker.

## Pattern

```ts
provisionTenantCustomHostname(input) -> { cf_hostname_id, status, ownership_challenge }
getCustomHostnameStatus(input)       -> { status }   // poll after DNS challenge added
```

## Usage

```ts
import {
  provisionTenantCustomHostname,
  getCustomHostnameStatus,
} from "@wave-av/foundation/frameworks/cf-custom-domain-tenant";

// 1) Tenant wants app.acme.com to point at WAVE.
const ch = await provisionTenantCustomHostname({
  tenant_id: "acme",
  hostname: "app.acme.com",
  account_id: env.CF_ACCOUNT_ID,
  zone_id: env.CF_ZONE_ID,
  api_token: env.CF_API_TOKEN,
});
// ch.status === "pending_validation" is EXPECTED here, not an error.
// Surface ch.ownership_challenge to the tenant: they must add a TXT record.

// 2) After tenant adds the DNS challenge, poll status until "active":
const s = await getCustomHostnameStatus({
  tenant_id: "acme",
  zone_id: env.CF_ZONE_ID,
  cf_hostname_id: ch.cf_hostname_id,
  api_token: env.CF_API_TOKEN,
});
if (s.status === "active") { /* hostname live */ }
```

## Reserved WAVE hostnames

The wrapper rejects any tenant attempt to claim WAVE-owned domains:
- `.wave.online`, `.wave.app`, `.wave.dev` suffix
- `wave.online`, `wave.app`, `wave.dev` exact

This prevents a tenant from pre-empting WAVE's own apex via the SSL-for-SaaS pipeline.

## Security

- `tenant_id` regex `/^[a-zA-Z0-9_-]{1,64}$/`
- `hostname` regex restricts to valid DNS labels + bans WAVE-owned suffixes (path-traversal-safe)
- `account_id`, `zone_id`, `cf_hostname_id` all 32-hex (CF format)
- `api_token` ≥30 chars (CF tokens are typically ≥40)
- `validation_method` whitelist (`http` / `txt` / `email`)

## Test plan

```bash
npx vitest run frameworks/cf-custom-domain-tenant
```

## Refs

- Task #204
- Pairs with WAVE Routes / Dispatch tenant binding
- Pairs with A18b CF Worker Routes (deferred — not in initial scaffold set)
