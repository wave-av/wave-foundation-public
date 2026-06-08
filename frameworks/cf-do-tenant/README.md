# Cloudflare Durable Objects Per-Tenant

Wrapper that derives DO ids from `(tenant_id, logical_name)` so two tenants requesting the same logical name get **different** DO instances by construction.

## The trap this prevents

```ts
// WRONG — two tenants will collide if they both call this with "session-default":
const id = env.SESSIONS.idFromName("session-default");
const stub = env.SESSIONS.get(id);
```

## Pattern

```ts
const sessions = new TenantDOClient(env.SESSIONS, tenant_id);
const stub = sessions.for("session-default");  // safe; namespaced to tenant_id
```

## Usage

```ts
import { TenantDOClient } from "@wave-av/foundation/frameworks/cf-do-tenant";

export default {
  async fetch(req: Request, env: { SESSIONS: DurableObjectNamespace }) {
    const tenant_id = req.headers.get("x-wave-tenant-id") ?? "anon";
    const sessions = new TenantDOClient(env.SESSIONS, tenant_id);

    const stub = sessions.for(`session:${userId}`);
    return stub.fetch(req);
  },
};
```

## Why no `provision()`?

DO namespaces are declared in `wrangler.toml` at deploy time, not via API. There's nothing to provision at runtime — the safety primitive is the **wrapper**, which prevents tenant_id collisions in id derivation.

## Test plan

```bash
npx vitest run frameworks/cf-do-tenant
```

## Refs

- Task #195
- Pairs with A8 cf-kv-tenant (KV for cold lookups, DO for hot state)
- Pairs with A7 cf-calls-platform (session state for WebRTC sessions)
