// provision-database.ts
//
// Creates a CF D1 database per tenant via the CF API.

import { D1TenantError, ProvisionedD1Database, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const HEX32_REGEX = /^[a-f0-9]{32}$/i;
const CF_API_BASE = "https://api.cloudflare.com/client/v4";

export interface ProvisionInput {
  tenant_id: TenantId;
  cf_account_id: string;
  cf_api_token: string;
  /** Optional location hint (CF D1 region). */
  primary_location_hint?: "wnam" | "enam" | "weur" | "eeur" | "apac" | "oc";
}

export async function provisionTenantD1Database(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedD1Database> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new D1TenantError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!HEX32_REGEX.test(input.cf_account_id)) {
    throw new D1TenantError("invalid cf_account_id", "INVALID_ACCOUNT_ID");
  }
  if (!input.cf_api_token || input.cf_api_token.length < 32) {
    throw new D1TenantError("invalid cf_api_token", "INVALID_TOKEN");
  }

  const database_name = `wave-tenant-${input.tenant_id}`;

  let res: Response;
  try {
    res = await fetchImpl(`${CF_API_BASE}/accounts/${input.cf_account_id}/d1/database`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.cf_api_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name: database_name,
        primary_location_hint: input.primary_location_hint,
      }),
    });
  } catch (err) {
    throw new D1TenantError("cf d1 create fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new D1TenantError(
      `cf d1 create ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : res.status === 409 ? "DATABASE_EXISTS" : "API_ERROR",
    );
  }

  const body = (await res.json()) as { success: boolean; result?: { uuid: string } };
  if (!body.success || !body.result?.uuid) {
    throw new D1TenantError("cf d1 no result", "INVALID_RESPONSE");
  }

  const binding_name =
    `TENANT_${input.tenant_id.toUpperCase().replace(/-/g, "_")}_DB`.slice(0, 64);

  return {
    tenant_id: input.tenant_id,
    cf_account_id: input.cf_account_id,
    database_id: body.result.uuid,
    database_name,
    binding_name,
    created_at: new Date().toISOString(),
  };
}
