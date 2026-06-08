# Metronome Per-Tenant Customer

Per-tenant Metronome customer + usage-event ingestion. Foundation for WAVE's "usage → invoice"
pipeline — every billable event (video minutes, calls, AI tokens, storage) lands in Metronome
attributed to the right customer.

## Pattern

```ts
provisionTenantMetronomeCustomer(input) -> { customer_id, ingest_alias }  // at signup
ingestUsageEvents(api_key, events)                                        // continuous
```

## Usage

```ts
import {
  provisionTenantMetronomeCustomer,
  ingestUsageEvents,
} from "@wave-av/foundation/frameworks/metronome-tenant-customer";

// 1) On signup:
const cust = await provisionTenantMetronomeCustomer({
  tenant_id: "acme",
  api_key: env.METRONOME_API_KEY,
});
// Persist cust.customer_id + cust.ingest_alias next to the tenant record.

// 2) Anytime usage occurs:
await ingestUsageEvents(env.METRONOME_API_KEY, [
  {
    customer_id: cust.customer_id,
    event_type: "wave.video.minutes",
    timestamp: new Date().toISOString(),
    transaction_id: `wave:acme:video:${sessionId}:${chunkIdx}`,
    properties: { minutes: "12.5", room: "live-1" },
  },
]);
```

## Idempotency

`transaction_id` is the Metronome dedup key — they hold it for 7 days. WAVE convention:
`wave:<tenant_id>:<event_type>:<resource_id>:<chunk_id>`. Retries with the same
`transaction_id` are safe and will NOT double-bill.

## Security

- `tenant_id` matches `/^[a-zA-Z0-9_-]{1,64}$/`.
- `event_type` matches `/^[a-z][a-z0-9_.]{0,127}$/` — blocks accidental display strings or
  user-controlled values from leaking into billable-metric names.
- `transaction_id` matches `/^[A-Za-z0-9_:.-]{1,128}$/`.
- Batches capped at 100 events (Metronome's per-request limit) and 50 properties per event.
- `ingest_alias` is forced to `wave:<tenant_id>` — deterministic, never user-supplied.

## Why an "ingest_alias" (vs just customer_id)?

Worker code that emits usage events shouldn't have to round-trip a customer-fetch to learn the
Metronome `customer_id`. The deterministic alias `wave:<tenant_id>` is known at code-generation
time, so a Worker only needs the `tenant_id` from the request to emit billable events.

## Test plan

```bash
npx vitest run frameworks/metronome-tenant-customer
```

## Refs

- Task #200
- Pairs with A12/A13 (WAVE Phone usage attribution)
- Pairs with A16/A17 (Anthropic + OpenRouter token attribution)
- Source for invoices generated against Stripe Connect (A1)
