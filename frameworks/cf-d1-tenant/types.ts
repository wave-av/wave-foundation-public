// Shared types for Cloudflare D1 per-tenant.
// D1 is CF's edge SQLite. For for-Platforms, each tenant gets their own D1 DB.
// Lighter-weight alternative to A4-style Supabase-for-Platforms — same isolation, lower price
// for small workloads.

export type TenantId = string;

export interface ProvisionedD1Database {
  tenant_id: TenantId;
  cf_account_id: string;
  database_id: string;            // CF D1 UUID
  database_name: string;          // wave-tenant-<tenant_id>
  binding_name: string;           // wrangler binding suggestion
  created_at: string;
}

export class D1TenantError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "D1TenantError";
  }
}
