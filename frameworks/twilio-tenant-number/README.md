# Twilio Per-Tenant Number Allocation

Allocate + release Twilio phone numbers ON a tenant's subaccount (provisioned via
`twilio-tenant-subaccount`). Numbers belong to the subaccount so billing, recordings,
and suspension stay tenant-isolated.

## Pattern

```ts
provisionTenantTwilioNumber(input) -> { number_sid, phone_number, ... }  // search + buy
releaseTenantTwilioNumber(input)   -> { released_at }                    // churn / swap
```

## Usage

```ts
import {
  provisionTenantTwilioNumber,
  releaseTenantTwilioNumber,
} from "@wave-av/foundation/frameworks/twilio-tenant-number";

// On signup / number-add:
const num = await provisionTenantTwilioNumber({
  tenant_id: "acme",
  subaccount_sid: tenant.twilio_subaccount_sid,
  subaccount_auth_token: tenant.twilio_subaccount_auth_token,  // from Doppler tenant-namespace
  country: "US",
  area_code: "415",
  required_capabilities: ["voice", "sms"],
  voice_url: "https://dispatch.wave.online/v1/phone/webhook/acme",
  sms_url:   "https://dispatch.wave.online/v1/phone/webhook/acme",
});

// Persist num.number_sid + num.phone_number against the tenant.

// On churn / number swap:
await releaseTenantTwilioNumber({
  tenant_id: "acme",
  subaccount_sid: tenant.twilio_subaccount_sid,
  subaccount_auth_token: tenant.twilio_subaccount_auth_token,
  number_sid: num.number_sid,
});
```

## Why allocate on the subaccount (not master)?

- Billing for the number, MRC, and per-minute/per-SMS usage routes to the subaccount → clean
  Metronome pass-through.
- Recordings, transcriptions, and call logs are isolated to the subaccount.
- Suspending a tenant suspends their numbers without touching others.
- A2P 10DLC brand/campaign registration is per-subaccount.

## Security

- `tenant_id` matches `/^[a-zA-Z0-9_-]{1,64}$/` — blocks path traversal in the friendly name.
- `subaccount_sid` matches `/^AC[a-f0-9]{32}$/` and is validated before being used in the URL.
- `number_sid` matches `/^PN[a-f0-9]{32}$/` on release.
- `voice_url` / `sms_url` MUST be `https://` — `http://` rejected at the wrapper, not relied on Twilio.
- `subaccount_auth_token` ≥ 30 chars — catches accidental empty-string pass-through.
- Returned `phone_number` is re-validated against E.164.

## Test plan

```bash
npx vitest run frameworks/twilio-tenant-number
```

## Refs

- Task #199
- Depends on A12 [`twilio-tenant-subaccount`](../twilio-tenant-subaccount/README.md) (subaccount must exist first)
- Pairs with A14 [`metronome-tenant-customer`](../metronome-tenant-customer/) (billing pass-through)
- WAVE Phone product line
