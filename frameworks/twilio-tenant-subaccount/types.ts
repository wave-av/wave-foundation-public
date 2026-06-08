// Shared types for Twilio per-tenant subaccount.
// Each WAVE-Phone customer gets a Twilio subaccount, so their numbers, recordings, billing,
// and SMS/voice traffic are administratively isolated from other customers.

export type TenantId = string;

export interface ProvisionedTwilioSubaccount {
  tenant_id: TenantId;
  account_sid: string;        // AC...
  auth_token: string;         // returned ONCE — store encrypted
  friendly_name: string;
  status: "active" | "suspended" | "closed";
  date_created: string;
}

export class TwilioSubaccountError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "TwilioSubaccountError";
  }
}
