// Shared types for Cloudflare KV per-tenant namespace.
// Each tenant gets its own KV namespace; the wrapper enforces a key prefix
// (`<tenant_id>:`) so a misconfigured namespace lookup can't cross tenants.

export type TenantId = string;

export interface ProvisionedKvNamespace {
  tenant_id: TenantId;
  cf_account_id: string;
  namespace_id: string;
  binding_name: string;          // suggested wrangler binding name
  created_at: string;
}

export class KvTenantError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "KvTenantError";
  }
}
