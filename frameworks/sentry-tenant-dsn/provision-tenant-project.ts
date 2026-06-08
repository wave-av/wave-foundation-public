// provision-tenant-project.ts
//
// One-call creation of a per-tenant Sentry project + first DSN.
// Returns the DSN to plug into the tenant's worker init.
//
// Sentry API ref:
//   POST /api/0/teams/{org_slug}/{team_slug}/projects/ -> {id, slug}
//   POST /api/0/projects/{org_slug}/{project_slug}/keys/ -> {dsn: {public}, id}

import { ProvisionedSentryProject, SentryTenantError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const SLUG_REGEX = /^[a-z0-9-]{1,50}$/;
const SENTRY_API_BASE = "https://sentry.io/api/0";

export interface ProvisionInput {
  tenant_id: TenantId;
  /** Sentry org slug, e.g. "wave-online-llc". */
  org_slug: string;
  /** Sentry team slug within the org, e.g. "platform". */
  team_slug: string;
  /** Project platform — sentry's platform identifier (node, javascript, etc.). */
  platform?: string;
}

export async function provisionTenantSentryProject(
  sentryAuthToken: string,
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedSentryProject> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new SentryTenantError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!SLUG_REGEX.test(input.org_slug) || !SLUG_REGEX.test(input.team_slug)) {
    throw new SentryTenantError("invalid org/team slug", "INVALID_SLUG");
  }
  if (!sentryAuthToken || sentryAuthToken.length < 20) {
    throw new SentryTenantError("invalid sentry auth token", "INVALID_TOKEN");
  }

  const project_slug = `tenant-${input.tenant_id}`.toLowerCase().slice(0, 50);

  let projectRes: Response;
  try {
    projectRes = await fetchImpl(
      `${SENTRY_API_BASE}/teams/${encodeURIComponent(input.org_slug)}/${encodeURIComponent(input.team_slug)}/projects/`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${sentryAuthToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: `Tenant: ${input.tenant_id}`,
          slug: project_slug,
          platform: input.platform ?? "node",
        }),
      },
    );
  } catch (err) {
    throw new SentryTenantError("sentry project create fetch failed", "FETCH_FAILED", err);
  }

  if (!projectRes.ok) {
    const text = await safeText(projectRes);
    throw new SentryTenantError(
      `sentry project create ${projectRes.status}: ${text}`,
      projectRes.status === 409 ? "PROJECT_EXISTS" : "PROJECT_CREATE_FAILED",
    );
  }

  const project = (await projectRes.json()) as { id: number; slug: string };

  // The first DSN ("Default") is auto-created on project creation. Fetch it to return.
  let keysRes: Response;
  try {
    keysRes = await fetchImpl(
      `${SENTRY_API_BASE}/projects/${encodeURIComponent(input.org_slug)}/${encodeURIComponent(project.slug)}/keys/`,
      {
        method: "GET",
        headers: { "Authorization": `Bearer ${sentryAuthToken}` },
      },
    );
  } catch (err) {
    throw new SentryTenantError("sentry keys fetch failed", "FETCH_FAILED", err);
  }

  if (!keysRes.ok) {
    throw new SentryTenantError(
      `sentry keys ${keysRes.status}`,
      "KEYS_FETCH_FAILED",
    );
  }

  const keys = (await keysRes.json()) as Array<{ id: number; dsn: { public: string } }>;
  if (keys.length === 0) {
    throw new SentryTenantError("no DSN returned from sentry", "NO_DSN");
  }

  return {
    tenant_id: input.tenant_id,
    sentry_org_slug: input.org_slug,
    sentry_project_slug: project.slug,
    sentry_project_id: project.id,
    dsn_public: keys[0].dsn.public,
    dsn_id: keys[0].id,
    created_at: new Date().toISOString(),
  };
}

async function safeText(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 500);
  } catch {
    return "<unreadable body>";
  }
}
