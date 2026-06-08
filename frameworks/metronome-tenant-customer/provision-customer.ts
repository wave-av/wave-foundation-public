// provision-customer.ts
//
// Create a Metronome customer for a tenant. The customer's "ingest_alias" is forced to a
// deterministic value derived from tenant_id so usage events sent with the alias are guaranteed
// to attribute to the right customer even before the customer_id round-trips.

import { MetronomeError, ProvisionedMetronomeCustomer, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const METRONOME_API_BASE = "https://api.metronome.com/v1";

export interface ProvisionInput {
  tenant_id: TenantId;
  api_key: string;
  /** Display name in the Metronome dashboard. */
  name?: string;
  /** Optional external_id passed through to Metronome. Defaults to `wave:<tenant_id>`. */
  external_id?: string;
}

export async function provisionTenantMetronomeCustomer(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedMetronomeCustomer> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new MetronomeError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!input.api_key || input.api_key.length < 20) {
    throw new MetronomeError("invalid metronome api_key", "INVALID_API_KEY");
  }

  const ingestAlias = `wave:${input.tenant_id}`;
  const externalId = input.external_id ?? ingestAlias;
  const name = input.name ?? `wave-tenant-${input.tenant_id}`;

  let res: Response;
  try {
    res = await fetchImpl(`${METRONOME_API_BASE}/customers`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.api_key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name,
        external_id: externalId,
        ingest_aliases: [ingestAlias],
      }),
    });
  } catch (err) {
    throw new MetronomeError("metronome fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new MetronomeError(
      `metronome customer create ${res.status}`,
      res.status === 401
        ? "UNAUTHORIZED"
        : res.status === 409
          ? "CUSTOMER_EXISTS"
          : "API_ERROR",
    );
  }

  const body = (await res.json()) as { data?: { id?: string; created_at?: string } };
  const customerId = body.data?.id;
  if (!customerId) {
    throw new MetronomeError("metronome returned no customer id", "API_ERROR");
  }

  return {
    tenant_id: input.tenant_id,
    customer_id: customerId,
    ingest_alias: ingestAlias,
    date_created: body.data?.created_at ?? new Date().toISOString(),
  };
}
