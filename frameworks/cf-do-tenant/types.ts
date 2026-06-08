// Shared types for Cloudflare Durable Objects per-tenant.
// DOs are stateful primitives; for-Platforms isolates per-tenant by deterministic id-derivation
// (DO id = SHA-256(tenant_id || ":" || logical_name)) so two tenants requesting the same
// logical_name get DIFFERENT DO instances.

export type TenantId = string;

export interface TenantDoBinding {
  binding: string;     // Worker binding name, e.g. "SESSIONS"
  class_name: string;  // DO class name in the worker's source
}

export class DoTenantError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "DoTenantError";
  }
}
