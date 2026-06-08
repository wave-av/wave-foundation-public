# Twilio Per-Tenant Subaccount

Per-tenant Twilio subaccount + webhook configuration. Foundation for WAVE Phone — each customer gets administratively isolated numbers, SMS/voice traffic, billing, and recordings.

## Pattern

```ts
provisionTenantTwilioSubaccount(input) -> { account_sid, auth_token }  // at signup
configureTenantWebhooks(input)                                          // wire webhooks to dispatch
```

## Usage

```ts
import {
  provisionTenantTwilioSubaccount,
  configureTenantWebhooks,
} from "@wave-av/foundation/frameworks/twilio-tenant-subaccount";

// 1) On signup:
const sub = await provisionTenantTwilioSubaccount({
  tenant_id: "acme",
  master_account_sid: env.TWILIO_MASTER_ACCOUNT_SID,
  master_auth_token: env.TWILIO_MASTER_AUTH_TOKEN,
});
// Persist sub.account_sid + encrypted sub.auth_token next to the tenant record
// (use doppler-tenant-namespace for the token).

// 2) Point inbound voice/SMS to WAVE dispatch:
await configureTenantWebhooks({
  tenant_id: "acme",
  subaccount_sid: sub.account_sid,
  subaccount_auth_token: sub.auth_token,
  voice_url: "https://dispatch.wave.online/v1/phone/webhook/acme",
  sms_url: "https://dispatch.wave.online/v1/phone/webhook/acme",
});
```

## Why subaccount per-tenant (not just number-per-tenant on master)?

- **Independent billing**: Twilio billing rolls up to subaccount; we pass through cleanly to Metronome.
- **Independent auth tokens**: tenant compromise doesn't expose master's auth.
- **Independent suspension**: can suspend a tenant without touching others.
- **Compliance**: per-subaccount call-recording, A2P 10DLC registration, and number ownership.

## Security

- master_account_sid + master_auth_token shape-validated.
- voice/SMS URLs forced to https.
- auth_token returned by provision MUST be stored encrypted (Doppler tenant-namespace).

## Test plan

```bash
npx vitest run frameworks/twilio-tenant-subaccount
```

## Refs

- Task #198
- Pairs with A13 twilio-tenant-number (number allocation)
- Pairs with A14 metronome-tenant-customer (billing pass-through)
- WAVE Phone product line
