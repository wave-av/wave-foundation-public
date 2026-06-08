# Hook0 Per-Tenant App

Per-tenant Hook0 application + event emit wrapper. Hook0 is an open-source
webhooks-as-a-service: applications hold subscribers, events are dispatched + signed +
retried by Hook0 itself.

## Pattern

```ts
provisionTenantHook0App(input) -> { application_id, application_secret }  // at signup
emitHook0Event(input)                                                     // continuous
```

## Usage

```ts
import {
  provisionTenantHook0App,
  emitHook0Event,
} from "@wave-av/foundation/frameworks/hook0-tenant-app";

// 1) Signup:
const app = await provisionTenantHook0App({
  tenant_id: "acme",
  base_url: env.HOOK0_BASE_URL,           // https://app.hook0.com or self-hosted
  organization_id: env.HOOK0_ORG_ID,
  api_token: env.HOOK0_API_TOKEN,
});
// Persist app.application_id + app.application_secret (encrypted) per tenant.

// 2) Emit an event:
await emitHook0Event({
  base_url: env.HOOK0_BASE_URL,
  application_secret: tenant.hook0_application_secret,
  event: {
    event_id: crypto.randomUUID(),
    event_type: "wave.session.recording_ready",
    occurred_at: new Date().toISOString(),
    payload: { session_id: "sess_abc", url: "https://r2.wave.online/..." },
    labels: { kind: "recording" },
  },
});
```

## Tenant isolation

`application_secret` is the scoping primitive — events emitted with tenant A's secret can
**only** fan out to tenant A's subscribers. Cross-tenant delivery is structurally
impossible. Same isolation pattern as A14 Metronome but for webhooks.

## Security

- `tenant_id` regex; `application_secret` ≥20 chars; `base_url` https-only
- `organization_id` must be UUID
- `event_id` must be UUID (idempotency key for Hook0 dedupe)
- `event_type` lowercase regex blocks display-string injection
- 256KB payload cap prevents runaway events
- 401 → UNAUTHORIZED; 409 → APP_EXISTS

## Test plan

```bash
npx vitest run frameworks/hook0-tenant-app
```

## Refs

- Task #206
- Pattern parallel to A14 metronome-tenant-customer (scoped secret → tenant-only delivery)
- Pairs with A19 resend-inbound-tenant (webhook **inbound**)
