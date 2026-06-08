// Shared types for the PostHog per-tenant team scaffold.
// Each WAVE tenant gets its own PostHog "project" (called "team" in the API) under the WAVE org,
// so funnels/cohorts/dashboards isolate per tenant.

export type TenantId = string;

export interface ProvisionedPosthogTeam {
  tenant_id: TenantId;
  posthog_team_id: number;
  posthog_team_name: string;       // "Tenant: <tenant_id>"
  posthog_api_token: string;       // public — embed in client SDK
  posthog_share_url?: string;      // optional team-share for the tenant operator
  posthog_org_id: string;
  created_at: string;
}

export class PostHogTenantError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "PostHogTenantError";
  }
}
