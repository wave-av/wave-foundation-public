// types.ts
//
// Per-tenant Twilio number allocation types. Numbers MUST be purchased on the tenant's
// subaccount (provisioned via twilio-tenant-subaccount), never on the master, so that
// billing, recordings, and suspension stay isolated.

export type TenantId = string;

export type NumberCapability = "voice" | "sms" | "mms" | "fax";

export interface ProvisionedTwilioNumber {
  tenant_id: TenantId;
  subaccount_sid: string;
  number_sid: string;
  phone_number: string;
  friendly_name: string;
  capabilities: {
    voice: boolean;
    sms: boolean;
    mms: boolean;
    fax: boolean;
  };
  voice_url: string | null;
  sms_url: string | null;
  date_created: string;
}

export type TwilioNumberErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_SUB_SID"
  | "INVALID_AUTH_TOKEN"
  | "INVALID_AREA_CODE"
  | "INVALID_COUNTRY"
  | "INVALID_CAPABILITY"
  | "INVALID_PHONE_NUMBER"
  | "INVALID_URL"
  | "NO_NUMBERS_AVAILABLE"
  | "UNAUTHORIZED"
  | "FETCH_FAILED"
  | "API_ERROR";

export class TwilioNumberError extends Error {
  constructor(
    message: string,
    public readonly code: TwilioNumberErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "TwilioNumberError";
  }
}
