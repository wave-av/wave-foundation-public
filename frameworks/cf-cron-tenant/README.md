# CF Cron Per-Tenant

Per-tenant cron jobs on Cloudflare. CF Cron Triggers are wrangler-time bindings — they
can't be added per tenant via API. Solution:

1. A **global Worker** has one `scheduled()` handler (e.g. every minute).
2. That handler calls `runDueTenantCrons(...)` which scans this KV-backed registry and
   POSTs to the tenant-scoped `target_url` for crons whose `cron_expr` matches the
   current minute.

This gives WAVE one global knob to throttle / audit / cancel tenant crons.

## Pattern

```ts
const reg = new TenantCronRegistry(tenantId, env.CRON_KV, {
  allowed_dispatch_hosts: ["dispatch.wave.online"],   // HARD allowlist (anti-SSRF)
});
reg.create(...)        // tenant adds a cron
reg.list()             // list this tenant's crons
reg.setEnabled(id,...) // pause/resume
reg.delete(id)         // remove

// In the global Worker scheduled() handler:
await runDueTenantCrons({
  kv: env.CRON_KV,
  allowed_dispatch_hosts: ["dispatch.wave.online"],
  signing_key: env.CRON_HMAC_SIGNING_KEY,   // server-only, ≥32 chars
});
```

## Usage

```ts
import { TenantCronRegistry, runDueTenantCrons } from "@wave-av/foundation/frameworks/cf-cron-tenant";

// Tenant adds a cron:
const reg = new TenantCronRegistry("acme", env.CRON_KV, {
  allowed_dispatch_hosts: ["dispatch.wave.online"],
});
await reg.create({
  cron_id: "daily-summary",
  cron_expr: "0 9 * * *",  // 09:00 UTC daily
  target_url: "https://dispatch.wave.online/v1/tenant/acme/cron/daily-summary",
  payload: { kind: "summary" },
});

// Global Worker scheduled handler (wrangler `[triggers] crons = ["* * * * *"]`):
export default {
  async scheduled(_ev, env) {
    const r = await runDueTenantCrons({
      kv: env.CRON_KV,
      allowed_dispatch_hosts: ["dispatch.wave.online"],
      signing_key: env.CRON_HMAC_SIGNING_KEY,
    });
    console.log(`cron tick: scanned=${r.scanned} matched=${r.matched} fired=${r.fired} failed=${r.failed} blocked=${r.skipped_blocked_host}`);
  },
};
```

## SSRF + credential-exfil defense (A21b)

`target_url` is tenant-controlled. Without defenses, a tenant could register
`https://attacker.example/exfil` and the global cron worker would POST tenant data
(plus any forwarded credentials) to attacker-controlled hosts. Two layers protect this:

1. **Host allowlist** at both `create()` time **and** at fire-time
   (`runDueTenantCrons` re-asserts as defense-in-depth). Hostname matched **exact +
   case-insensitive** — `dispatch.wave.online.attacker.example` is rejected. Also rejects
   `http://`, userinfo (`https://attacker@dispatch.wave.online`), and non-default ports.
2. **No shared bearer token.** Each call is signed with a per-call HMAC-SHA256 of
   `<tenant_id>|<cron_id>|<fired_at_iso>|<payload_sha256>` using a server-only signing
   key. Dispatch verifies. A leaked HMAC is bound to that exact tenant/cron/timestamp
   and cannot be replayed across tenants or against other endpoints.

Headers emitted to dispatch:
- `X-Wave-Tenant-Id`
- `X-Wave-Cron-Id`
- `X-Wave-Cron-Fired-At`
- `X-Wave-Cron-Payload-SHA256`
- `X-Wave-Cron-Signature: v1,<base64-hmac>`

## Tenant isolation

- Keys in KV use `<tenant_id>:<cron_id>`. `TenantCronRegistry.list()` always scopes by
  the tenant's prefix so one tenant cannot enumerate another's crons.
- Per-call HMAC is bound to the tenant id — cross-tenant replay is structurally impossible.
- Payload is capped at 32KB.

## Security

- `tenant_id` + `cron_id` regex `/^[a-zA-Z0-9_-]{1,64}$/`
- `cron_expr` validator: exactly 5 fields of allowed chars (digits, `*`, `,`, `/`, `-`)
- `target_url` host-allowlisted, https-only, no userinfo, no non-default port
- `signing_key` ≥32 chars

## Test plan

```bash
npx vitest run frameworks/cf-cron-tenant
```

## Refs

- Task #207 (A21) + task #228 (A21b SSRF/HMAC hardening)
- Pairs with cf-do-tenant (state) + cf-d1-tenant (results)
- Cron expr validator local — avoids extra dep on `cron-parser`
- Security lesson class shared with A5b (any tenant-controlled URL or query-language input
  needs adversarial-input tests in PR #1)
