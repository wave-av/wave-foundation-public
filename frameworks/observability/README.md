# WAVE Observability Standard

> How every WAVE spoke reports errors, raises ops alerts, and routes user feedback — one pattern,
> consumed not copied. Reference implementation: [`scaffolder/templates/observability/notify.ts`](../../scaffolder/templates/observability/notify.ts),
> proven in prod as `wave-av/wave-dispatch:edge-router/notify.ts`.

## Package (preferred): `@wave-av/observability`

The executable implementation now ships as a published package — [`packages/observability`](../../packages/observability/README.md),
`@wave-av/observability` on GitHub Packages. **Prefer importing it over copying `notify.ts`:**

```ts
import { notifyOps, forwardFeedback } from "@wave-av/observability";        // dep-free core
import { captureException } from "@wave-av/observability/worker";           // CF Workers
import { initOtel } from "@wave-av/observability/node";                     // Node/Next.js OTel spans
```

The `service` tag is a runtime value (`env.WAVE_SERVICE` / `OTEL_SERVICE_NAME`) instead of the
scaffold-time `__REPO_NAME__` substitution. The `scaffolder/templates/observability/notify.ts` copy
remains as the zero-install fallback for repos that can't add the dependency, but new repos should
consume the package. Same three sinks, same contract below.

## Principles

1. **Observability never breaks the path it observes.** Every sink call is `try/catch` and returns a
   boolean/array — it **never throws**. A dead Sentry or a 500 from Linear must not 500 the request.
2. **Flag-gated OFF by default.** Each sink is a no-op until its env var is set. A freshly-scaffolded
   spoke ships the helper inert; wiring a DSN is what turns it on. No config → no behavior change.
3. **Never forward a secret.** `message`/`extra` are sent verbatim to third parties. Never pass a
   license key (`wv_*`), API key, token, or raw auth header into them. Pass plan/status/`email_domain`,
   not the credential.
4. **No SDK on the edge.** The helper speaks Sentry's HTTP store API and Linear's GraphQL directly, so
   it runs unchanged on Cloudflare Workers, Node, and Bun with zero dependencies and zero cold-start cost.
5. **One Sentry project per spoke.** Errors are attributable by service without tag-spelunking. See the
   registry below.

## The three sinks

| Sink | Env var(s) | Purpose | Helper |
|------|-----------|---------|--------|
| **Sentry** | `SENTRY_DSN` | ops errors / alerts | `notifyOps(env, msg, extra, level)` |
| **Linear** | `LINEAR_API_KEY` + `LINEAR_TEAM_ID` | user feedback/reports → issues | `createLinearIssue(env, title, desc)` |
| **Webhook** | `OPS_WEBHOOK_URL` | generic catch-all (Slack/Discord/Intercom) | fan-out inside `notifyOps` |

The webhook fan-out is **destination-aware**: a `hooks.slack.com` URL gets a Slack `{text}` body and a
Discord webhook gets a `{content}` body (both a one-line `🔴 [level] service — message`), because those
endpoints reject any other shape with HTTP 400. Any other URL (Intercom/Zapier/custom) receives the
full structured `source / kind / level / message / extra` JSON. So `OPS_WEBHOOK_URL` can be pointed at a
Slack incoming webhook directly — no relay needed.

`forwardFeedback(env, rec)` composes them: feedback → Linear; a `bug` ALSO raises an ops alert so an
engineer sees it. It returns the list of sinks attempted (informational, for the JSON response).

## Wiring a spoke

1. **Scaffold** copies `observability/notify.ts` in (placeholders `__REPO_NAME__` are substituted to the
   repo slug, which becomes the Sentry `service` tag + `sentry_client`).
2. **Import and call** on the paths that matter — at minimum a prod-failure path and a feedback route:

   ```ts
   import { notifyOps, forwardFeedback } from "./observability/notify";

   // a prod failure you want to know about (best-effort; don't await-block the response if hot):
   ctx.waitUntil(notifyOps(env, "syncAccount failed", { plan, status, email_domain }, "error"));

   // a user feedback/report route:
   const sinks = await forwardFeedback(env, rec);   // -> ["linear","alert"]
   ```

3. **Set the envs** in the spoke's own secret store (Doppler config / `wrangler secret put` / Vercel env).
   Until then everything is a silent no-op — which is the correct safe default.

### Sentry DSN → store endpoint (why no SDK is needed)

A DSN is `https://<public_key>@<host>/<project_id>`. The helper derives the ingest endpoint
`https://<host>/api/<project_id>/store/` and authenticates with `sentry_key=<public_key>` in the
`x-sentry-auth` header. The public key is a client-side ingest key (safe to ship in edge code); it is
**not** an org-management secret.

## Sentry project registry

Each spoke gets its own project under the **`wave-online-llc`** Sentry org (region `us`). Create new
ones with `mcp sentry create_project` (or the dashboard); store the returned DSN as the `SENTRY_DSN`
**Cloudflare Worker secret** (`wrangler secret put SENTRY_DSN`, or the CF API) — CF Worker secrets
survive `wrangler deploy`, so the wiring is durable without touching deploy workflows. **Never commit a
DSN into the repo.**

The authoritative **project → worker** map is [`scripts/observability/spoke-sentry-map.tsv`](../../scripts/observability/spoke-sentry-map.tsv)
(no DSNs — fetched live from Sentry). It is the single source of truth for which project a spoke reports
into, so a new spoke doesn't create a duplicate or report into the wrong project.

### Bulk / repeatable provisioning

[`scripts/observability/wire-sentry-dsn.sh`](../../scripts/observability/wire-sentry-dsn.sh) reads that
map, ensures each project exists, fetches its DSN, and writes the `SENTRY_DSN` Worker secret on every
listed worker. Idempotent and safe (the secret only feeds best-effort `notifyOps`, which never throws):

```sh
doppler run --project wave --config prd -- \
  bash scripts/observability/wire-sentry-dsn.sh scripts/observability/spoke-sentry-map.tsv
```

Needs a `wave-online-llc` Sentry token with `project:read/write/admin` (`SENTRY_PROVISION_TOKEN`, tracked
in task OBS-F1) plus `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`. If no scoped Sentry token is
available, create the projects via the Sentry MCP first and run with `--skip-project`.

### Drift check (regression net)

[`scripts/observability/check-sentry-coverage.sh`](../../scripts/observability/check-sentry-coverage.sh)
is read-only (lists secret + worker NAMES, never values) and enforces two things, exiting non-zero on
either miss:

- **Coverage** — every worker in the map carries a `SENTRY_DSN` secret (so `notify.ts` is not a no-op).
- **Completeness** — every *live* Worker on the CF account is in the map. A map-only check can't see a
  newly-deployed spoke nobody added to the map; it would ship dark. The script lists all live workers
  and flags any absent from the map (minus an explicit `IGNORE_WORKERS` set of non-app redirect/holding/
  template workers). This is what prevents the gap from silently re-opening as new spokes land.

```sh
doppler run --project wave --config prd -- bash scripts/observability/check-sentry-coverage.sh
```

**Mount it to run unattended** on a host that already has Doppler + CF creds (the Studio cron, alongside
the other unattended obs jobs) — **not** as a hosted GitHub Actions job, which would mean placing a
`CLOUDFLARE_API_TOKEN` in Actions secrets (an avoidable secrets-surface). On a miss it should alert via
the same `notifyOps`/`OPS_WEBHOOK_URL` channel it guards.

> **Fleet status (2026-06-06):** all **49** live application Workers on the spoke CF account are wired
> with a per-spoke DSN (task #52/#76); `notifyOps` is live fleet-wide. The completeness check caught
> `wave-web-www-production` live-but-unmapped and it was added + wired. DSNs live only in each Worker's
> CF secret store, not here. **Gotcha:** the CF secrets API returns HTTP **201** on a first-time CREATE
> (200 on update) — both are success.

## What this standard intentionally does NOT mandate

- **Distributed tracing / session replay / release health.** Richer Sentry features are opt-in per spoke
  (harvested patterns live in `staging/observability/` and `memories/observability/`). This standard is
  the floor every spoke meets, not the ceiling.
- **A metrics pipeline.** Counters/histograms federate through `api.wave.online`; a spoke does not stand
  up its own Prometheus.

## Source & provenance

This pattern was extracted from `wave-av/wave-dispatch:edge-router/notify.ts` (#25/#26), which has run in
production since 2026-05. The dispatch copy remains the canonical reference for behavior; changes to the
standard land here first, then dispatch and other spokes re-consume.
