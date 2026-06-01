# Identity + Money — Phase 1 — Foundation

Five canonical primitives every WAVE consumer's identity layer inherits. Phase 1 ships **schema only** — Phase 2 wires linking, Phase 3 wires payment, Phase 4 wires the unified audit query layer. The shapes here are designed so all four phases compose without migrating populated tables.

## Why ship the standard from the foundation

WSC is the consuming database; every WAVE product federates against it. If each product invents its own user table, scope grammar, or audit envelope, the cross-product audit (Phase 4) is impossible. The foundation owns the **shape**; each consumer applies it to their Supabase project.

## What ships

| Migration | Provides |
|-----------|----------|
| [`001_canonical_user_model.sql`](./migrations/001_canonical_user_model.sql) | `public.user_profiles` (1:1 with `auth.users`) + RLS |
| [`002_scope_grammar.sql`](./migrations/002_scope_grammar.sql) | `auth.has_scope(text[], text)` — single matcher for all RLS |
| [`003_tenant_model.sql`](./migrations/003_tenant_model.sql) | `public.tenants` + `public.user_tenant_memberships` + RLS |
| [`004_actor_chain.sql`](./migrations/004_actor_chain.sql) | `auth.actor_chain_has_scope(jwt, text)` — RFC 8693 intersection |
| [`005_audit_envelope.sql`](./migrations/005_audit_envelope.sql) | `public.audit_events` (append-only) + RLS |

## Applying to a Supabase project

```bash
# From your consuming repo (with .foundation vendored). Two supported paths:
#
# (a) Copy the migrations into supabase/migrations/ and let the CLI push them:
mkdir -p supabase/migrations
for m in .foundation/frameworks/identity-money/phase-1/migrations/*.sql; do
  cp "$m" supabase/migrations/
done
supabase db push --linked   # applies any pending files in supabase/migrations/
#
# (b) Apply directly via psql against your linked project (no copy needed):
for m in .foundation/frameworks/identity-money/phase-1/migrations/*.sql; do
  psql "$SUPABASE_DB_URL" -f "$m"
done
#
# Or via the Supabase MCP server (staging first, never direct-write prod):
# Apply each migration to the staging project; PR-merge to prod path.
```

Then run the schema-conformance gate locally to verify:

```bash
bash .foundation/scripts/check-identity-schema.sh --supabase-url ... --service-role ...
```

## The five primitives (recap)

1. **Canonical user model** — `auth.users` ↔ `public.user_profiles` (1:1), tenant_id NOT NULL, category constrained, Phase-2/3 FK columns ship nullable so later phases don't migrate populated rows
2. **Scope grammar** — `<product>:<verb>:<noun>[:<modifier>]` with `:any` wildcard and `admin:any` master shortcut, single `auth.has_scope()` function used by every RLS policy
3. **Tenant model** — N:M memberships from day one; `wave-av` bootstrap tenant inserted
4. **Actor chain** — JWT `act` chain walked recursively; intersection rule (every actor must hold the scope independently)
5. **Audit envelope** — append-only events with full `actor_chain[]`, before/after, scope_used, dpop_thumbprint, trace_id

## Verifying conformance

The `scripts/check-identity-schema.sh` gate connects to a Supabase project and verifies the five primitives are present + correctly shaped. The dogfood gate `identity_phase1_schema_present` only checks foundation-side artifacts (the migrations + README exist + parse).

```bash
# Foundation-side (no network):
bash scripts/check-identity-schema.sh --offline   # schema files present + valid SQL

# Consumer-side (against a real Supabase project):
SUPABASE_URL=https://<project-ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
bash scripts/check-identity-schema.sh
```

## Cross-references

- [`docs/superpowers/specs/2026-05-28-identity-money-program-overview.md`](../../../docs/superpowers/specs/2026-05-28-identity-money-program-overview.md) — overall design
- [`rules/identity-policy.md`](../../../rules/identity-policy.md) — agent-vs-human routing policy
- [`scripts/check-identity-schema.sh`](../../../scripts/check-identity-schema.sh) — schema conformance gate
- Phase 2 — linking (KYC, credentials), Phase 3 — payment, Phase 4 — unified audit query
