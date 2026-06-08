// provision-app.ts
//
// Create a Hook0 application for a tenant. Returns an application-scoped secret used to
// ingest events for that tenant only — preventing cross-tenant fan-out by construction.

import { Hook0Error, ProvisionedHook0App, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const URL_REGEX = /^https:\/\/[^\s]+$/;

export interface ProvisionInput {
  tenant_id: TenantId;
  /** Hook0 base URL (e.g. https://app.hook0.com or self-hosted). */
  base_url: string;
  /** Hook0 organization the new application will belong to. */
  organization_id: string;
  /** API token bound to the organization. */
  api_token: string;
}

export async function provisionTenantHook0App(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedHook0App> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new Hook0Error("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!URL_REGEX.test(input.base_url)) {
    throw new Hook0Error("base_url must be https", "INVALID_BASE_URL");
  }
  if (!UUID_REGEX.test(input.organization_id)) {
    throw new Hook0Error("organization_id must be UUID", "INVALID_ORG_ID");
  }
  if (!input.api_token || input.api_token.length < 30) {
    throw new Hook0Error("invalid api_token", "INVALID_API_TOKEN");
  }

  const baseUrl = input.base_url.replace(/\/+$/, "");
  let res: Response;
  try {
    res = await fetchImpl(`${baseUrl}/api/v1/applications`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.api_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name: `wave-tenant-${input.tenant_id}`,
        organization_id: input.organization_id,
      }),
    });
  } catch (err) {
    throw new Hook0Error("hook0 fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new Hook0Error(
      `hook0 app create ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : res.status === 409 ? "APP_EXISTS" : "API_ERROR",
    );
  }

  const body = (await res.json()) as {
    application_id?: string;
    application_secret?: string;
    created_at?: string;
  };
  if (!body.application_id || !body.application_secret) {
    throw new Hook0Error("hook0 returned malformed app", "API_ERROR");
  }

  return {
    tenant_id: input.tenant_id,
    application_id: body.application_id,
    application_secret: body.application_secret,
    date_created: body.created_at ?? new Date().toISOString(),
  };
}
