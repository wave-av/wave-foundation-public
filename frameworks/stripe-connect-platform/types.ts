// Shared types for the Stripe Connect platform scaffold.
// Customer-facing: a WAVE tenant becomes a Stripe Connect "connected account" so the tenant
// can accept payments through WAVE without holding their own Stripe credentials at boot.

export type TenantId = string;

export interface ProvisionedAccount {
  tenant_id: TenantId;
  stripe_account_id: string; // acct_…
  onboarding_url: string; // single-use, expires per Stripe TTL
  webhook_endpoint_id: string; // we_…
  created_at: string; // ISO
}

export interface OnboardingStatus {
  tenant_id: TenantId;
  stripe_account_id: string;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  details_submitted: boolean;
  requirements_due: string[]; // missing fields per Stripe
}

export class StripeConnectError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "StripeConnectError";
  }
}
