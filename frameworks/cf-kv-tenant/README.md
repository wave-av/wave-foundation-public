# Cloudflare KV Per-Tenant

Per-tenant CF Workers KV namespace + safe-prefix client. Edge config / small state per tenant.

## Two isolation modes

1. **Namespace per tenant** — `provisionTenantKvNamespace()` creates a dedicated namespace.
   Strongest isolation but each namespace is a billable resource.
2. **Shared namespace, prefix isolation** — `TenantKVClient` wraps a shared binding with a forced
   `<tenant_id>:` key prefix on every read/write/list. Cost-effective; isolation is enforced by
   the wrapper, not by CF.

The two modes compose: a tenant gets its own namespace AND uses `TenantKVClient` for defense-in-depth.

## Pattern

```ts
provisionTenantKvNamespace(input) -> { namespace_id, binding_name }
new TenantKVClient(env.TENANT_KV, "acme") -> safe client
```

## Usage

```ts
import {
  provisionTenantKvNamespace,
  TenantKVClient,
} from "@wave-av/foundation/frameworks/cf-kv-tenant";

// On signup:
const kv = await provisionTenantKvNamespace({
  tenant_id: "acme",
  cf_account_id: env.CF_ACCOUNT_ID,
  cf_api_token: env.CF_KV_API_TOKEN,
});
// Operator wires `[[kv_namespaces]]` entry in wrangler.toml with binding=kv.binding_name and id=kv.namespace_id.

// In the tenant worker:
const client = new TenantKVClient(env.TENANT_KV, "acme");
await client.put("session:abc", JSON.stringify({ user_id: "u1" }), { expirationTtl: 3600 });
const v = await client.get("session:abc", { type: "json" });
```

## Security

- Tenant-id regex blocks path-traversal in slug.
- Key regex blocks unicode/special chars from causing key collisions.
- `list()` always force-prefixes; caller-provided prefix is appended.
- expirationTtl bounded `>= 60s`.

## Test plan

```bash
npx vitest run frameworks/cf-kv-tenant
```

## Refs

- Task #194
- Pairs with A9 cf-do-tenant (Durable Objects for stateful sessions; KV for cold lookups).
- Pairs with A10 cf-d1-tenant (D1 for relational small-data).
