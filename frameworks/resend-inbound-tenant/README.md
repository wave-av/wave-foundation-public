# Resend Per-Tenant Inbound Email

Per-tenant Resend inbound route + signature verification. Inbound counterpart to A2
outbound `resend-customer-domain`.

## Pattern

```ts
provisionTenantInboundRoute(input)            // at signup
verifyInboundWebhook(input)  -> InboundEmail  // per inbound POST
```

## Usage

```ts
import {
  provisionTenantInboundRoute,
  verifyInboundWebhook,
} from "@wave-av/foundation/frameworks/resend-inbound-tenant";

// 1) On signup:
const route = await provisionTenantInboundRoute({
  tenant_id: "acme",
  api_key: env.RESEND_API_KEY,
  base_domain: "inbound.wave.online",
});
// Persist route.route_id + route.webhook_secret (encrypted) per tenant.
// route.webhook_url is always https://dispatch.wave.online/v1/inbound/<tenant_id>.

// 2) In the inbound webhook handler at dispatch.wave.online/v1/inbound/:tenant_id:
const email = await verifyInboundWebhook({
  tenant_id,
  webhook_secret: tenantWebhookSecret,  // from Doppler tenant-namespace
  raw_body: rawBody,                    // EXACT bytes — never re-stringified JSON
  svix_id:        req.headers["svix-id"],
  svix_timestamp: req.headers["svix-timestamp"],
  svix_signature: req.headers["svix-signature"],
});
// Now we know this inbound truly belongs to tenant `tenant_id`.
```

## Why signature verification is tenant-isolation-critical

Without verifying the Svix signature, anyone POSTing JSON to
`/v1/inbound/<tenant_id>` could forge inbound email for that tenant. The wrapper:

- Requires all three Svix headers (`svix-id`, `svix-timestamp`, `svix-signature`).
- Enforces 5-minute timestamp tolerance against replay.
- HMAC-SHA256 over `<msg_id>.<timestamp>.<raw_body>` — base64, timing-safe compare.
- Accepts multiple space-separated `v1,<sig>` candidates per Svix spec.

The `webhook_url` is **forced** by the wrapper — callers cannot override it. This prevents
a tenant from being routed to another tenant's worker.

## Security

- `tenant_id` regex `/^[a-zA-Z0-9_-]{1,64}$/`
- `api_key` must start with `re_` and be ≥20 chars
- `base_domain` strict DNS regex
- Webhook secret never logged
- Timing-safe signature comparison

## Test plan

```bash
npx vitest run frameworks/resend-inbound-tenant
```

## Refs

- Task #205
- Pairs with A2 resend-customer-domain (outbound)
- Pairs with A20 hook0-tenant-app (alternative webhook delivery pattern reference)
- Webhook URL points at WAVE dispatch (api.wave.online/v1/inbound/<tenant_id>)
