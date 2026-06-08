// provision-namespace.ts
//
// Creates a CF Workers KV namespace dedicated to a tenant.

import { KvTenantError, ProvisionedKvNamespace, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const HEX32_REGEX = /^[a-f0-9]{32}$/i;
const CF_API_BASE = "https://api.cloudflare.com/client/v4";

export interface ProvisionInput {
  tenant_id: TenantId;
  cf_account_id: string;
  cf_api_token: string;
  /** Suggested binding-name. Defaults to "TENANT_<UPPER_TENANT_ID>_KV". */
  binding_name?: string;
}

export async function provisionTenantKvNamespace(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedKvNamespace> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new KvTenantError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!HEX32_REGEX.test(input.cf_account_id)) {
    throw new KvTenantError("invalid cf_account_id", "INVALID_ACCOUNT_ID");
  }
  if (!input.cf_api_token || input.cf_api_token.length < 32) {
    throw new KvTenantError("invalid cf_api_token", "INVALID_TOKEN");
  }

  const binding =
    input.binding_name ??
    `TENANT_${input.tenant_id.toUpperCase().replace(/-/g, "_")}_KV`.slice(0, 64);
  if (!/^[A-Z][A-Z0-9_]{0,63}$/.test(binding)) {
    throw new KvTenantError("invalid binding_name", "INVALID_BINDING");
  }

  let res: Response;
  try {
    res = await fetchImpl(`${CF_API_BASE}/accounts/${input.cf_account_id}/storage/kv/namespaces`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.cf_api_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ title: `wave-tenant-${input.tenant_id}` }),
    });
  } catch (err) {
    throw new KvTenantError("cf kv create fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new KvTenantError(
      `cf kv create ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : res.status === 409 ? "NAMESPACE_EXISTS" : "API_ERROR",
    );
  }

  const body = (await res.json()) as { success: boolean; result?: { id: string } };
  if (!body.success || !body.result?.id) {
    throw new KvTenantError("cf kv no result", "INVALID_RESPONSE");
  }

  return {
    tenant_id: input.tenant_id,
    cf_account_id: input.cf_account_id,
    namespace_id: body.result.id,
    binding_name: binding,
    created_at: new Date().toISOString(),
  };
}
