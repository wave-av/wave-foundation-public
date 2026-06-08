// client-wrapper.ts
//
// Init helper that selects the right Sentry DSN at boot based on the tenant_id.
// The tenant→DSN mapping comes from the caller (typically a Supabase lookup or Doppler).
//
// Usage:
//   const dsn = await resolveTenantDsn(tenant_id);
//   Sentry.init({ dsn, ... });

import { SentryTenantError, TenantId } from "./types.js";

export type DsnResolver = (tenant_id: TenantId) => Promise<string | null>;

export interface ResolveOptions {
  resolver: DsnResolver;
  /** Optional fallback (shared WAVE DSN) used when the tenant has no project yet. */
  fallback_dsn?: string;
}

export async function resolveTenantDsn(
  tenant_id: TenantId,
  options: ResolveOptions,
): Promise<string> {
  const dsn = await options.resolver(tenant_id);
  if (dsn) return dsn;
  if (options.fallback_dsn) return options.fallback_dsn;
  throw new SentryTenantError(
    `no DSN for tenant_id=${tenant_id} and no fallback configured`,
    "NO_DSN_RESOLVED",
  );
}
