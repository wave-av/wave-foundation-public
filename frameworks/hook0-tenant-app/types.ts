// types.ts
//
// Hook0 per-tenant application types. Each tenant gets a dedicated Hook0 application
// (group of webhooks/subscribers); events emitted with that application's key fan out
// only to that tenant's subscribers. Cross-tenant fan-out is structurally impossible.

export type TenantId = string;

export interface ProvisionedHook0App {
  tenant_id: TenantId;
  application_id: string;
  /** Application-scoped API key used to ingest events for this tenant. */
  application_secret: string;
  date_created: string;
}

export interface Hook0Event {
  event_id: string;
  event_type: string;
  occurred_at: string;
  /** Arbitrary JSON-serializable payload (will be wrapped in Hook0's envelope). */
  payload: Record<string, unknown>;
  /** Optional labels for subscriber filtering — Hook0 ANDs these against subscription filters. */
  labels?: Record<string, string>;
}

export type Hook0ErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_ORG_ID"
  | "INVALID_API_TOKEN"
  | "INVALID_APP_SECRET"
  | "INVALID_BASE_URL"
  | "INVALID_EVENT_ID"
  | "INVALID_EVENT_TYPE"
  | "INVALID_TIMESTAMP"
  | "PAYLOAD_TOO_LARGE"
  | "UNAUTHORIZED"
  | "APP_EXISTS"
  | "FETCH_FAILED"
  | "API_ERROR";

export class Hook0Error extends Error {
  constructor(
    message: string,
    public readonly code: Hook0ErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "Hook0Error";
  }
}
