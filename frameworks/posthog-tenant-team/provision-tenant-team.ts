// provision-tenant-team.ts
//
// Creates a per-tenant PostHog project (the API calls projects "teams") under the WAVE org.
// Returns the public api_token (client-embeddable) plus team_id for downstream wiring.
//
// PostHog API:
//   POST /api/organizations/:org_id/projects/  -> { id, name, api_token }
//   (Personal API key required — "Project Management" scope.)

import { PostHogTenantError, ProvisionedPosthogTeam, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;

export interface ProvisionInput {
  tenant_id: TenantId;
  /** PostHog org UUID — find via /api/organizations/@current/. */
  org_id: string;
  /** PostHog host. Default: https://app.posthog.com. EU: https://eu.posthog.com. Self-host: any URL. */
  posthog_host?: string;
}

export async function provisionTenantPosthogTeam(
  personalApiKey: string,
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedPosthogTeam> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new PostHogTenantError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!/^[a-f0-9-]{20,}$/i.test(input.org_id)) {
    throw new PostHogTenantError("invalid org_id (expect UUID)", "INVALID_ORG_ID");
  }
  if (!personalApiKey || personalApiKey.length < 20) {
    throw new PostHogTenantError("invalid personal api key", "INVALID_API_KEY");
  }

  const host = sanitizeHost(input.posthog_host ?? "https://app.posthog.com");
  const name = `Tenant: ${input.tenant_id}`;

  let res: Response;
  try {
    res = await fetchImpl(`${host}/api/organizations/${encodeURIComponent(input.org_id)}/projects/`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${personalApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ name }),
    });
  } catch (err) {
    throw new PostHogTenantError("posthog fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    const text = await safeText(res);
    throw new PostHogTenantError(
      `posthog ${res.status}: ${text}`,
      res.status === 401 ? "UNAUTHORIZED" : res.status === 403 ? "FORBIDDEN" : "API_ERROR",
    );
  }

  const body = (await res.json()) as { id?: number; name?: string; api_token?: string };
  if (!body.id || !body.api_token) {
    throw new PostHogTenantError("posthog returned no team id / token", "INVALID_RESPONSE");
  }

  return {
    tenant_id: input.tenant_id,
    posthog_team_id: body.id,
    posthog_team_name: body.name ?? name,
    posthog_api_token: body.api_token,
    posthog_org_id: input.org_id,
    created_at: new Date().toISOString(),
  };
}

function sanitizeHost(host: string): string {
  // Strip trailing slash; require https
  const u = new URL(host);
  if (u.protocol !== "https:") {
    throw new PostHogTenantError("posthog_host must be https", "INVALID_HOST");
  }
  return u.origin;
}

async function safeText(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 500);
  } catch {
    return "<unreadable body>";
  }
}
