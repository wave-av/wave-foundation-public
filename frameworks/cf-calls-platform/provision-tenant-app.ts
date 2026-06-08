// provision-tenant-app.ts
//
// Creates a CF Calls App for a tenant. Each app has its own ID + secret + isolated sessions.

import { CallsPlatformError, ProvisionedCallsApp, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const HEX32_REGEX = /^[a-f0-9]{32}$/i;
const CF_API_BASE = "https://api.cloudflare.com/client/v4";

export interface ProvisionInput {
  tenant_id: TenantId;
  cf_account_id: string;
  cf_api_token: string;
}

export async function provisionTenantCallsApp(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedCallsApp> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new CallsPlatformError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!HEX32_REGEX.test(input.cf_account_id)) {
    throw new CallsPlatformError("invalid cf_account_id", "INVALID_ACCOUNT_ID");
  }
  if (!input.cf_api_token || input.cf_api_token.length < 32) {
    throw new CallsPlatformError("invalid cf_api_token", "INVALID_TOKEN");
  }

  let res: Response;
  try {
    res = await fetchImpl(`${CF_API_BASE}/accounts/${input.cf_account_id}/calls/apps`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.cf_api_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ name: `wave-tenant-${input.tenant_id}` }),
    });
  } catch (err) {
    throw new CallsPlatformError("cf calls app create fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new CallsPlatformError(
      `cf calls app create ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : res.status === 409 ? "APP_EXISTS" : "API_ERROR",
    );
  }

  const body = (await res.json()) as { success: boolean; result?: { uid: string; secret: string } };
  if (!body.success || !body.result?.uid || !body.result?.secret) {
    throw new CallsPlatformError("cf calls app no result", "INVALID_RESPONSE");
  }

  return {
    tenant_id: input.tenant_id,
    cf_app_id: body.result.uid,
    cf_app_secret: body.result.secret,
    cf_account_id: input.cf_account_id,
    created_at: new Date().toISOString(),
  };
}
