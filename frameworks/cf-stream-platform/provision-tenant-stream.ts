// provision-tenant-stream.ts
//
// Creates a Stream signing key for a tenant. We DO NOT create a separate API token per tenant
// (that requires admin:zone scope CF only grants interactively) — instead we share WAVE's
// Stream-scoped API token across tenants and rely on per-tenant signing keys + meta-tagging
// (every upload gets `meta.wave_tenant_id`) to isolate.

import { ProvisionedStreamTenant, StreamPlatformError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const CF_API_BASE = "https://api.cloudflare.com/client/v4";

export interface ProvisionInput {
  tenant_id: TenantId;
  cf_account_id: string;
  cf_api_token: string;
}

export async function provisionTenantStream(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedStreamTenant> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new StreamPlatformError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!/^[a-f0-9]{32}$/i.test(input.cf_account_id)) {
    throw new StreamPlatformError("invalid cf_account_id", "INVALID_ACCOUNT_ID");
  }
  if (!input.cf_api_token || input.cf_api_token.length < 32) {
    throw new StreamPlatformError("invalid cf_api_token", "INVALID_TOKEN");
  }

  // Create a signing key dedicated to this tenant. Signed URLs include kid + tenant context.
  let res: Response;
  try {
    res = await fetchImpl(`${CF_API_BASE}/accounts/${input.cf_account_id}/stream/keys`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.cf_api_token}`,
        "Content-Type": "application/json",
      },
    });
  } catch (err) {
    throw new StreamPlatformError("cf stream key create fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new StreamPlatformError(
      `cf stream key create ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  const body = (await res.json()) as {
    success: boolean;
    result?: { id: string; pem: string; jwk: unknown };
  };

  if (!body.success || !body.result) {
    throw new StreamPlatformError("cf stream key create returned no result", "INVALID_RESPONSE");
  }

  return {
    tenant_id: input.tenant_id,
    cf_api_token_id: input.cf_api_token.slice(0, 8) + "…", // hint only; never echo full token
    cf_account_id: input.cf_account_id,
    signing_key_id: body.result.id,
    signing_key_pem: body.result.pem,
    created_at: new Date().toISOString(),
  };
}
