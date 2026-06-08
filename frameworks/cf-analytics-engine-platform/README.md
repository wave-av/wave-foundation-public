# Cloudflare Analytics Engine for Platforms

Per-tenant attribution on top of a shared CF Analytics Engine dataset. Cheaper than dataset-per-tenant; AE pricing rewards shared datasets, and we tag every event with `tenant_id` as `index1` so queries can be forcibly scoped.

## Pattern

```ts
writeTenantEvent(env.ANALYTICS, { tenant_id, blobs, doubles })  // safe writer (always tags)
queryTenantAnalytics({ account_id, api_token, tenant_id, dataset, select_clause, ... })  // forced WHERE
```

## Usage

```ts
import {
  writeTenantEvent,
  queryTenantAnalytics,
} from "@wave-av/foundation/frameworks/cf-analytics-engine-platform";

// In the customer worker, on every event:
export default {
  async fetch(req: Request, env: { ANALYTICS: AEDataset }) {
    writeTenantEvent(env.ANALYTICS, {
      tenant_id: "acme",
      extra_indexes: ["page_view"],
      blobs: [req.url, req.headers.get("user-agent")],
      doubles: [Date.now()],
    });
    return new Response("ok");
  },
};

// From WAVE-platform admin UI, query a specific tenant:
const result = await queryTenantAnalytics({
  account_id: env.CF_ACCOUNT_ID,
  api_token: env.CF_API_TOKEN,
  tenant_id: "acme",
  dataset: "wave_customer_events",
  select_clause: "blob1 AS path, count() AS hits",
  group_by: "blob1",
  order_by: "hits DESC",
  limit: 100,
  since_iso: "2026-06-01T00:00:00Z",
});
```

## Security

`queryTenantAnalytics` **forces** `WHERE index1 = '<tenant_id>'` as the first condition. Callers cannot bypass it. The select/where/group/order/limit clauses are validated against a narrow character allowlist to prevent injection. `tenant_id` is single-quote-escaped before interpolation.

## Test plan

```bash
npx vitest run frameworks/cf-analytics-engine-platform
```

## Refs

- Task #191 / #169
- Pairs with A11 `cf-workers-ai-tenant` (LLM cost events also go here)
- Pairs with A14 `metronome-tenant-customer` (events can drive Metronome usage)
