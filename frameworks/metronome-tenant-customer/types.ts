// types.ts
//
// Metronome per-tenant customer + usage ingestion types.
// Metronome billing model: one customer_id per tenant; usage events carry
// {customer_id, event_type, timestamp, properties, transaction_id} and the
// transaction_id is the idempotency key — Metronome dedupes for 7 days.

export type TenantId = string;

export interface ProvisionedMetronomeCustomer {
  tenant_id: TenantId;
  customer_id: string;
  ingest_alias: string;
  date_created: string;
}

export interface UsageEvent {
  /** Stable customer_id returned by provisionTenantMetronomeCustomer. */
  customer_id: string;
  /** Metronome billable-metric name (e.g. "wave.video.minutes"). */
  event_type: string;
  /** RFC3339 timestamp. */
  timestamp: string;
  /** Idempotency key. Metronome dedupes on (customer_id, event_type, transaction_id). */
  transaction_id: string;
  /** Numeric/string properties referenced by Metronome billable-metric formula. */
  properties: Record<string, string | number>;
}

export type MetronomeErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_API_KEY"
  | "INVALID_INGEST_ALIAS"
  | "INVALID_EVENT_TYPE"
  | "INVALID_TIMESTAMP"
  | "INVALID_TRANSACTION_ID"
  | "INVALID_PROPERTIES"
  | "EMPTY_BATCH"
  | "BATCH_TOO_LARGE"
  | "UNAUTHORIZED"
  | "CUSTOMER_EXISTS"
  | "FETCH_FAILED"
  | "API_ERROR";

export class MetronomeError extends Error {
  constructor(
    message: string,
    public readonly code: MetronomeErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "MetronomeError";
  }
}
