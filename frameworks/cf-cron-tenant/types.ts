// types.ts
//
// Per-tenant cron registry (logical, KV-backed). CF Cron Triggers are wrangler-time
// bindings on a Worker — not API-creatable per tenant. We solve this by:
//   1. A global Worker with a fixed `scheduled()` handler (e.g. every minute).
//   2. That handler calls runDueTenantCrons(...) which scans this registry and fans out
//      to tenant-scoped dispatch routes whose cron expressions match.
//
// This gives WAVE one global throttle/audit/cancel point for all tenant crons.

export type TenantId = string;

export interface TenantCron {
  cron_id: string;
  tenant_id: TenantId;
  /** 5-field POSIX cron expression (m h dom mon dow). */
  cron_expr: string;
  /** Dispatch route to POST when this cron fires, e.g.
   *  https://dispatch.wave.online/v1/tenant/<tenant>/cron/<cron_id> */
  target_url: string;
  /** JSON-serializable payload. Capped at 32KB. */
  payload: Record<string, unknown>;
  enabled: boolean;
  created_at: string;
  updated_at: string;
}

export type CronErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_CRON_ID"
  | "INVALID_CRON_EXPR"
  | "INVALID_TARGET_URL"
  | "PAYLOAD_TOO_LARGE"
  | "DISABLED"
  | "NOT_FOUND"
  | "FETCH_FAILED";

export class CronError extends Error {
  constructor(
    message: string,
    public readonly code: CronErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "CronError";
  }
}

/** Minimal KV-shape we need — a real CF KVNamespace satisfies this. */
export interface KVLike {
  get(key: string, opts?: { type: "json" }): Promise<unknown | null>;
  put(key: string, value: string): Promise<void>;
  delete(key: string): Promise<void>;
  list(opts?: { prefix?: string; limit?: number; cursor?: string }): Promise<{
    keys: Array<{ name: string }>;
    list_complete: boolean;
    cursor?: string;
  }>;
}
