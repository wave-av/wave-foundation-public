// issue-turn-credential.ts
//
// Issues short-lived TURN credentials for a tenant's session. CF Calls' TURN
// service signs credentials with the app secret + a TTL.

import { CallsPlatformError, TenantId, TurnCredential } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const CF_API_BASE = "https://api.cloudflare.com/client/v4";

export interface IssueInput {
  tenant_id: TenantId;
  cf_app_id: string;
  cf_app_secret: string;
  /** TTL in seconds. Default 86400 (24h). Max 86400. */
  ttl_seconds?: number;
}

export async function issueTenantTurnCredential(
  input: IssueInput,
  fetchImpl: typeof fetch = fetch,
): Promise<TurnCredential> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new CallsPlatformError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!input.cf_app_id || input.cf_app_id.length < 16) {
    throw new CallsPlatformError("invalid cf_app_id", "INVALID_APP_ID");
  }
  if (!input.cf_app_secret || input.cf_app_secret.length < 16) {
    throw new CallsPlatformError("invalid cf_app_secret", "INVALID_APP_SECRET");
  }
  const ttl = input.ttl_seconds ?? 86400;
  if (!Number.isInteger(ttl) || ttl < 60 || ttl > 86400) {
    throw new CallsPlatformError("ttl_seconds must be integer in [60, 86400]", "INVALID_TTL");
  }

  let res: Response;
  try {
    res = await fetchImpl(
      `${CF_API_BASE}/turn/keys/${encodeURIComponent(input.cf_app_id)}/credentials/generate-ice-servers`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${input.cf_app_secret}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ ttl }),
      },
    );
  } catch (err) {
    throw new CallsPlatformError("cf turn ice fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new CallsPlatformError(
      `cf turn ice ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  const body = (await res.json()) as {
    iceServers?: Array<{ urls: string | string[]; username?: string; credential?: string }>;
  };
  if (!body.iceServers || body.iceServers.length === 0) {
    throw new CallsPlatformError("cf turn returned no ice servers", "NO_ICE_SERVERS");
  }

  return {
    tenant_id: input.tenant_id,
    cf_app_id: input.cf_app_id,
    ice_servers: body.iceServers,
    expires_at: new Date(Date.now() + ttl * 1000).toISOString(),
  };
}
