// client-wrapper.ts
//
// Init helper that selects the right PostHog api_token at boot based on tenant_id.
// Lookup is caller-provided — typically Supabase or Doppler.

import { PostHogTenantError, TenantId } from "./types.js";

export type ApiTokenResolver = (tenant_id: TenantId) => Promise<string | null>;

export interface ResolveOptions {
  resolver: ApiTokenResolver;
  fallback_api_token?: string;
}

export async function resolveTenantPosthogToken(
  tenant_id: TenantId,
  options: ResolveOptions,
): Promise<string> {
  const token = await options.resolver(tenant_id);
  if (token) return token;
  if (options.fallback_api_token) return options.fallback_api_token;
  throw new PostHogTenantError(
    `no PostHog api_token for tenant_id=${tenant_id} and no fallback`,
    "NO_TOKEN_RESOLVED",
  );
}
