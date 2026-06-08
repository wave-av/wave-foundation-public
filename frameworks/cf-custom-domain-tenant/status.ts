// status.ts
//
// Poll the current status of a tenant's custom hostname. Use this after the tenant has
// added the ownership challenge to their DNS to detect transition from pending_validation
// → active.

import { CustomDomainError, HostnameStatus, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const CF_ZONE_ID_REGEX = /^[a-f0-9]{32}$/;
const CF_HOSTNAME_ID_REGEX = /^[a-f0-9]{32}$/;

export interface StatusInput {
  tenant_id: TenantId;
  zone_id: string;
  cf_hostname_id: string;
  api_token: string;
}

export async function getCustomHostnameStatus(
  input: StatusInput,
  fetchImpl: typeof fetch = fetch,
): Promise<{
  tenant_id: TenantId;
  hostname: string;
  status: HostnameStatus;
  fetched_at: string;
}> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new CustomDomainError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!CF_ZONE_ID_REGEX.test(input.zone_id)) {
    throw new CustomDomainError("invalid zone_id", "INVALID_ZONE_ID");
  }
  if (!CF_HOSTNAME_ID_REGEX.test(input.cf_hostname_id)) {
    throw new CustomDomainError("invalid cf_hostname_id", "API_ERROR");
  }
  if (!input.api_token || input.api_token.length < 30) {
    throw new CustomDomainError("invalid api_token", "INVALID_API_TOKEN");
  }

  let res: Response;
  try {
    res = await fetchImpl(
      `https://api.cloudflare.com/client/v4/zones/${encodeURIComponent(input.zone_id)}/custom_hostnames/${encodeURIComponent(input.cf_hostname_id)}`,
      {
        method: "GET",
        headers: { "Authorization": `Bearer ${input.api_token}` },
      },
    );
  } catch (err) {
    throw new CustomDomainError("cf custom-hostname status fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new CustomDomainError(
      `cf status ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  const body = (await res.json()) as {
    result?: { hostname?: string; status?: HostnameStatus };
  };
  if (!body.result?.hostname || !body.result.status) {
    throw new CustomDomainError("cf returned malformed status", "API_ERROR");
  }

  return {
    tenant_id: input.tenant_id,
    hostname: body.result.hostname,
    status: body.result.status,
    fetched_at: new Date().toISOString(),
  };
}
