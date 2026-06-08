# PostHog Per-Tenant Team for Platforms

Each WAVE tenant gets its own PostHog "team" (project) under the WAVE org, so the tenant's funnels, cohorts, retention, dashboards, and replay all isolate from other tenants' data.

## Pattern

```ts
provisionTenantPosthogTeam(personalKey, input) -> { posthog_api_token, posthog_team_id, ... }
resolveTenantPosthogToken(tenant_id, { resolver }) -> api_token  // for client init
```

## Usage

```ts
import {
  provisionTenantPosthogTeam,
  resolveTenantPosthogToken,
} from "@wave-av/foundation/frameworks/posthog-tenant-team";

// On signup:
const team = await provisionTenantPosthogTeam(process.env.POSTHOG_PERSONAL_API_KEY!, {
  tenant_id: "acme",
  org_id: "01234567-89ab-cdef-0123-456789abcdef",
});
// Persist team.posthog_api_token + team.posthog_team_id alongside the tenant record.

// In the tenant runtime:
const apiToken = await resolveTenantPosthogToken("acme", {
  resolver: async (id) => /* lookup in supabase */,
  fallback_api_token: process.env.SHARED_POSTHOG_TOKEN,
});
const posthog = new PostHog(apiToken, { host: "https://app.posthog.com" });
```

## Why per-team (not just tagging with tenant_id)?

- **Access control**: tenant can be given a share link to *their* team only.
- **Quota / rate limits**: PostHog quotas apply per-team, not per-event-tag, so noisy neighbors don't crowd out the rest.
- **Retention policies**: each tenant can set their own retention.
- **Feature flags**: per-team flag namespaces avoid collisions.

## Test plan

```bash
npx vitest run frameworks/posthog-tenant-team
```

## Refs

- Task #190 / #170
- Pairs with A3 sentry-tenant-dsn (observability twin)
- See WAVE org id in Doppler at `wave/prd/POSTHOG_ORG_ID`
