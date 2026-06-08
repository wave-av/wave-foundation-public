# Sentry Per-Tenant DSN for Platforms

Each WAVE tenant gets its own Sentry project under the WAVE org. Errors/perf isolation per tenant, Seer Code Review access per tenant, alerting per tenant.

## Pattern

```ts
provisionTenantSentryProject(authToken, input) -> { dsn_public, sentry_project_slug, ... }
resolveTenantDsn(tenant_id, { resolver }) -> dsn  // for init-time selection
```

## Usage

```ts
import {
  provisionTenantSentryProject,
  resolveTenantDsn,
} from "@wave-av/foundation/frameworks/sentry-tenant-dsn";

// On tenant signup:
const sentry = await provisionTenantSentryProject(process.env.SENTRY_AUTH_TOKEN!, {
  tenant_id: "acme",
  org_slug: "wave-online-llc",
  team_slug: "platform",
});
// Persist sentry.dsn_public + sentry.sentry_project_slug next to the tenant record.

// In the tenant worker at boot:
const dsn = await resolveTenantDsn("acme", {
  resolver: async (id) => {
    const row = await supabase
      .from("tenants")
      .select("sentry_dsn")
      .eq("id", id)
      .single();
    return row.data?.sentry_dsn ?? null;
  },
  fallback_dsn: process.env.SHARED_SENTRY_DSN,  // safety net
});
Sentry.init({ dsn, environment: "production", tracesSampleRate: 0.1 });
```

## Why this matters

Memory entry `wave-sentry-coverage-gap-2026-06-03.md` showed that only 4 of 48 live CF Workers had a DSN bound — 44 silent. A per-tenant DSN issuance pattern (this scaffold) lets the *deploy* step bind the DSN per-tenant deterministically, closing the gap by construction.

## Test plan

```bash
# Unit tests
npx vitest run frameworks/sentry-tenant-dsn

# Live dogfood (test tenant)
doppler run --project wave --config stg -- node -e '
  const { provisionTenantSentryProject } = await import("./frameworks/sentry-tenant-dsn/provision-tenant-project.js");
  const p = await provisionTenantSentryProject(process.env.SENTRY_AUTH_TOKEN, {
    tenant_id: "dogfood",
    org_slug: "wave-online-llc",
    team_slug: "platform",
  });
  console.log(JSON.stringify(p, null, 2));
'
```

## Related

- A14 `metronome-tenant-customer` — bills per tenant; Sentry events can drive billing alerts.
- `doppler-tenant-namespace` — stores per-tenant Sentry auth tokens if you want to rotate independently.
- See [[wave-sentry-coverage-gap-2026-06-03]] for the WAVE-internal Sentry gap this scaffold helps prevent for customers.
