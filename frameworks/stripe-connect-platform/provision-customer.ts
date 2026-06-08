// provision-customer.ts
//
// One-call onboarding for a new WAVE tenant onto Stripe Connect.
// Creates: Express account + account-onboarding link + webhook endpoint scoped to that account.
//
// Caller responsibilities:
//   - Pass the WAVE tenant_id (slug, ^[a-zA-Z0-9_-]{1,64}$).
//   - Persist the returned `stripe_account_id` next to the tenant record.
//   - Render the returned `onboarding_url` to the tenant's owner.
//
// What this does NOT do:
//   - Persist anything. Caller owns storage (uses doppler-tenant-namespace + Supabase per the
//     for-Platforms convention).
//   - Capture customer PII. The Express onboarding flow does that on Stripe's side.

import Stripe from "stripe";
import { ProvisionedAccount, StripeConnectError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;

export interface ProvisionInput {
  tenant_id: TenantId;
  /** Tenant's owner email — used for Stripe Account creation. */
  email: string;
  /** Onboarding return URL (after the tenant completes Stripe onboarding). */
  return_url: string;
  /** Onboarding refresh URL (link-expired retry). */
  refresh_url: string;
  /** Webhook URL on WAVE that Stripe should POST account.updated etc. to. */
  webhook_url: string;
  /** Optional: pre-fill country (ISO 3166-1 alpha-2). Stripe defaults to US if omitted. */
  country?: string;
}

export async function provisionCustomerStripeAccount(
  stripe: Stripe,
  input: ProvisionInput,
): Promise<ProvisionedAccount> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new StripeConnectError(
      `invalid tenant_id: must match ${TENANT_ID_REGEX}`,
      "INVALID_TENANT_ID",
    );
  }
  if (!isValidEmail(input.email)) {
    throw new StripeConnectError("invalid email", "INVALID_EMAIL");
  }
  if (!isHttpsUrl(input.return_url) || !isHttpsUrl(input.refresh_url) || !isHttpsUrl(input.webhook_url)) {
    throw new StripeConnectError(
      "return_url, refresh_url, webhook_url must all be https://",
      "INVALID_URL",
    );
  }

  let account: Stripe.Account;
  try {
    account = await stripe.accounts.create({
      type: "express",
      email: input.email,
      country: input.country,
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true },
      },
      metadata: { wave_tenant_id: input.tenant_id },
    });
  } catch (err) {
    throw new StripeConnectError("stripe.accounts.create failed", "ACCOUNT_CREATE_FAILED", err);
  }

  let onboarding: Stripe.AccountLink;
  try {
    onboarding = await stripe.accountLinks.create({
      account: account.id,
      type: "account_onboarding",
      return_url: input.return_url,
      refresh_url: input.refresh_url,
    });
  } catch (err) {
    throw new StripeConnectError(
      "stripe.accountLinks.create failed",
      "ACCOUNT_LINK_FAILED",
      err,
    );
  }

  let webhook: Stripe.WebhookEndpoint;
  try {
    webhook = await stripe.webhookEndpoints.create({
      url: input.webhook_url,
      connect: true,
      enabled_events: [
        "account.updated",
        "account.application.deauthorized",
        "capability.updated",
        "payout.failed",
        "payout.paid",
        "charge.dispute.created",
      ],
      metadata: { wave_tenant_id: input.tenant_id, wave_stripe_account_id: account.id },
    });
  } catch (err) {
    throw new StripeConnectError(
      "stripe.webhookEndpoints.create failed",
      "WEBHOOK_CREATE_FAILED",
      err,
    );
  }

  return {
    tenant_id: input.tenant_id,
    stripe_account_id: account.id,
    onboarding_url: onboarding.url,
    webhook_endpoint_id: webhook.id,
    created_at: new Date().toISOString(),
  };
}

function isValidEmail(s: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) && s.length <= 254;
}

function isHttpsUrl(s: string): boolean {
  try {
    return new URL(s).protocol === "https:";
  } catch {
    return false;
  }
}
