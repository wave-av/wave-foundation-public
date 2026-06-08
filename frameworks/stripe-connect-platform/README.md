# Stripe Connect for Platforms

WAVE-for-Platforms scaffold for **per-tenant Stripe Connect onboarding**.

When a WAVE customer (tenant) wants to accept payments through WAVE, we create a Stripe **Express** connected account for them. The tenant completes onboarding on Stripe's side; we keep their `stripe_account_id` next to their tenant record and route payment-related webhooks via a dedicated endpoint scoped to that account.

## Pattern

Every for-Platforms framework in `wave-foundation/frameworks/*-for-platforms/` exports the same shape:

```ts
provision(input) -> ProvisionedResource   // idempotent, returns IDs to persist
client(tenant_id) -> ScopedClient         // returns a tenant-scoped client at runtime
```

For Stripe Connect, the two halves are:

- `provisionCustomerStripeAccount` — runs once at tenant signup (returns onboarding URL).
- `getOnboardingStatus` — runs whenever you want to know if the tenant is ready to take charges.

## Usage

```ts
import Stripe from "stripe";
import {
  provisionCustomerStripeAccount,
  getOnboardingStatus,
} from "@wave-av/foundation/frameworks/stripe-connect-platform";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: "2025-09-30.preview" });

// On tenant signup:
const provisioned = await provisionCustomerStripeAccount(stripe, {
  tenant_id: "acme",
  email: "owner@acme.example",
  return_url: "https://wave.online/onboarding/return?tenant=acme",
  refresh_url: "https://wave.online/onboarding/refresh?tenant=acme",
  webhook_url: "https://api.wave.online/v1/stripe/webhook/acme",
  country: "US",
});

// Persist provisioned.stripe_account_id next to the tenant record
// (Supabase per-tenant schema, or Doppler tenant-namespace if simpler).
// Render provisioned.onboarding_url to the tenant operator.

// Later — gating UI:
const status = await getOnboardingStatus(stripe, "acme", provisioned.stripe_account_id);
if (status.charges_enabled) { /* show "ready to accept payments" */ }
```

## What this does NOT do

- **No persistence.** Caller stores `stripe_account_id` (and the webhook endpoint id, if revoking
  later) per their for-Platforms storage choice (Supabase / Doppler / etc.).
- **No webhook verification.** Use Stripe's standard verification at the handler — this scaffold
  only *creates* the webhook endpoint object; the actual receiver is owned by the caller.
- **No PII capture.** The Express onboarding URL handles every personal/business field on Stripe's
  side. We carry only the email used for the account.

## Related frameworks

- `supabase-for-platforms` — store `stripe_account_id` per tenant
- `doppler-tenant-namespace` — store Stripe-side secrets (e.g., `STRIPE_WEBHOOK_SIGNING_SECRET`)
- `customer-storage` — if you need to bucket payment-related blobs per tenant

## Tests

`tests/provision-customer.test.ts` covers:
- happy path returns ProvisionedAccount
- invalid tenant_id rejected
- non-HTTPS URLs rejected
- invalid email rejected
- account creation failure wrapped in `StripeConnectError`
- webhook creation failure wrapped in `StripeConnectError`

Run with `npx vitest run frameworks/stripe-connect-platform`.
