// onboarding-status.ts
//
// Read-only lookup: where is this tenant's Stripe onboarding right now?
//
// Useful for:
//   - Showing a status badge to the tenant operator
//   - Gating "can the tenant accept payments" in the WAVE UI
//   - Surfacing the Stripe-defined "requirements due" list verbatim so the operator can act

import Stripe from "stripe";
import { OnboardingStatus, StripeConnectError, TenantId } from "./types.js";

export async function getOnboardingStatus(
  stripe: Stripe,
  tenant_id: TenantId,
  stripe_account_id: string,
): Promise<OnboardingStatus> {
  let account: Stripe.Account;
  try {
    account = await stripe.accounts.retrieve(stripe_account_id);
  } catch (err) {
    throw new StripeConnectError(
      "stripe.accounts.retrieve failed",
      "ACCOUNT_RETRIEVE_FAILED",
      err,
    );
  }

  const requirements_due = [
    ...(account.requirements?.currently_due ?? []),
    ...(account.requirements?.past_due ?? []),
  ];

  return {
    tenant_id,
    stripe_account_id,
    charges_enabled: account.charges_enabled,
    payouts_enabled: account.payouts_enabled,
    details_submitted: account.details_submitted,
    requirements_due: Array.from(new Set(requirements_due)),
  };
}
