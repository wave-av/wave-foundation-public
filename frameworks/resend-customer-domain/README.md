# Resend Customer Domain for Platforms

Per-tenant sending domain (`mail.<tenant_id>.<base>`) on Resend so each WAVE tenant has isolated DKIM + SPF + deliverability reputation.

## Pattern

```ts
provisionTenantDomain(apiKey, input) -> { dns_records, sending_domain, resend_domain_id }
sendEmail(apiKey, { tenant_id, sending_domain, from_local_part, ... }) -> { message_id }
```

## Usage

```ts
import {
  provisionTenantDomain,
  sendEmail,
} from "@wave-av/foundation/frameworks/resend-customer-domain";

// On tenant signup:
const domain = await provisionTenantDomain(process.env.RESEND_API_KEY!, {
  tenant_id: "acme",
  base_domain: "wave.online",
  // sending_domain becomes: mail.acme.wave.online
});

// Tell the operator (or auto-publish via Cloudflare DNS API):
console.log("Publish these DNS records:", domain.dns_records);

// Later — actually sending:
const result = await sendEmail(process.env.RESEND_API_KEY!, {
  tenant_id: "acme",
  sending_domain: domain.sending_domain,
  from_local_part: "noreply",
  to: "user@example.com",
  subject: "Welcome",
  html: "<p>Welcome to Acme</p>",
});
```

## What this does NOT do

- **No DNS publishing.** Caller publishes DNS records (or chains to A18 `cf-custom-domain-tenant` if WAVE manages the tenant's zone).
- **No verification polling.** Caller polls Resend's `/domains/:id` until `status: verified`.
- **No template rendering.** Caller provides finished html/text. Use the for-Platforms email-template framework (TBD).

## Smoke test

```bash
RESEND_API_KEY=re_test_... npx vitest run frameworks/resend-customer-domain
```

## Live dogfood (operator-gated)

```bash
doppler run --project wave --config stg -- node -e '
  const { provisionTenantDomain } = await import("./frameworks/resend-customer-domain/provision-domain.js");
  const d = await provisionTenantDomain(process.env.RESEND_API_KEY, {
    tenant_id: "dogfood",
    base_domain: "wave.online",
  });
  console.log(JSON.stringify(d, null, 2));
'
```

## Related

- A18 `cf-custom-domain-tenant` — auto-publishes the returned `dns_records` if WAVE manages the zone
- A19 `resend-inbound-tenant` — inbound-side companion
- `doppler-tenant-namespace` — store per-tenant Resend webhook signing secret
