// Shared types for the Sentry per-tenant DSN scaffold.
// Each WAVE tenant gets its own Sentry project under the WAVE org, so error/perf
// isolation + Seer review access maps 1:1 with the tenant.

export type TenantId = string;

export interface ProvisionedSentryProject {
  tenant_id: TenantId;
  sentry_org_slug: string;       // e.g. "wave-online-llc"
  sentry_project_slug: string;   // e.g. "tenant-acme"
  sentry_project_id: number;
  dsn_public: string;            // https://<key>@oXXX.ingest.sentry.io/<projectId>
  dsn_id: number;
  created_at: string;
}

export class SentryTenantError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "SentryTenantError";
  }
}
