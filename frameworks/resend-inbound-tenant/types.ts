// types.ts
//
// Resend Inbound per-tenant types. Resend's inbound feature parses incoming email and POSTs
// a JSON payload (signed with Svix) to a configured webhook URL. The wrapper:
//   1. Provisions an inbound route per tenant whose webhook URL is forced to
//      https://dispatch.wave.online/v1/inbound/<tenant_id>.
//   2. Verifies the Svix signature on inbound webhooks so a forged POST cannot
//      impersonate a tenant's inbound email.

export type TenantId = string;

export interface ProvisionedInboundRoute {
  tenant_id: TenantId;
  route_id: string;
  /** Inbound address routed to this tenant (e.g. `acme@inbound.wave.online`). */
  inbound_address: string;
  webhook_url: string;
  /** Secret used to verify Svix signatures on inbound payloads. STORE ENCRYPTED. */
  webhook_secret: string;
  date_created: string;
}

export interface InboundEmail {
  tenant_id: TenantId;
  from: string;
  to: ReadonlyArray<string>;
  subject: string;
  text: string;
  html: string | null;
  received_at: string;
  message_id: string;
}

export type ResendInboundErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_API_KEY"
  | "INVALID_BASE_DOMAIN"
  | "INVALID_WEBHOOK_URL"
  | "MISSING_SIGNATURE_HEADER"
  | "MISSING_TIMESTAMP_HEADER"
  | "MISSING_ID_HEADER"
  | "TIMESTAMP_OUT_OF_TOLERANCE"
  | "INVALID_SIGNATURE"
  | "UNAUTHORIZED"
  | "ROUTE_EXISTS"
  | "FETCH_FAILED"
  | "API_ERROR";

export class ResendInboundError extends Error {
  constructor(
    message: string,
    public readonly code: ResendInboundErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "ResendInboundError";
  }
}
