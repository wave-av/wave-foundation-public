# Cloudflare D1 Per-Tenant

Per-tenant CF D1 (edge SQLite) database + safe prepared-statement wrapper. Lighter-weight Supabase alternative for customers whose data is small enough to fit comfortably in SQLite.

## Pattern

```ts
provisionTenantD1Database(input) -> { database_id, binding_name }
new TenantD1Client(env.TENANT_DB, "acme").prepare("SELECT * FROM users WHERE tenant_id = ? AND id = ?").bind("u1")
//                                                                                                    ^^^^ tenant_id auto-prepended
```

## Why force `?` placeholders?

`TenantD1Client.prepare()` rejects queries without `?` placeholders. This forces all dynamic values through bound params, eliminating string-interpolation SQL injection as a class.

The wrapper also auto-prepends `tenant_id` as the FIRST bound param. Callers write queries like:

```sql
SELECT * FROM sessions WHERE tenant_id = ? AND user_id = ?
```

and call:

```ts
client.prepare(SQL).bind(user_id).all()
```

The `tenant_id = ?` ALWAYS gets the correct tenant — caller can't forget to filter or pass the wrong id.

## Usage

```ts
import {
  provisionTenantD1Database,
  TenantD1Client,
} from "@wave-av/foundation/frameworks/cf-d1-tenant";

// At signup:
const d1 = await provisionTenantD1Database({
  tenant_id: "acme",
  cf_account_id: env.CF_ACCOUNT_ID,
  cf_api_token: env.CF_D1_API_TOKEN,
  primary_location_hint: "enam",
});

// In the customer worker:
const client = new TenantD1Client(env.TENANT_DB, "acme");
const stmt = client.prepare("SELECT id, name FROM users WHERE tenant_id = ? AND active = ?");
const rows = await stmt.bind(true).all(); // tenant_id auto-bound
```

## Test plan

```bash
npx vitest run frameworks/cf-d1-tenant
```

## Refs

- Task #196
- Alternative to supabase-for-platforms (heavier, full Postgres)
- Pairs with A8 cf-kv-tenant (KV for unstructured), A9 cf-do-tenant (DO for stateful hot path)
