# WAVE Observability Standard

> How every WAVE spoke reports errors, raises ops alerts, and routes user feedback — one pattern,
> consumed not copied. Reference implementation: [`scaffolder/templates/observability/notify.ts`](../../scaffolder/templates/observability/notify.ts),
> proven in prod as `wave-av/private-repo:edge-router/notify.ts`.

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
5. **One Sentry project per spoke.** Errors are attributable by service without tag-spelunking. (Moot
   while Sentry is retired — see "Sentry retired" below; the per-spoke registry was deleted.)

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

## Sentry retired (2026-09-23) — `obs-wire` is now a no-op

Sentry was cancelled by operator decision on 2026-09-23. The provisioning/drift-check tooling that used
to back this section — `scripts/observability/wire-sentry-dsn.sh`, `scripts/observability/check-sentry-coverage.sh`,
`scripts/observability/propose-sentry-map-row.sh`, and the `spoke-sentry-map.tsv` registry it read —
has been **deleted**, along with the `sentry-coverage-drift.yml` cron workflow that ran the drift check.
`notifyOps`'s Sentry sink itself is untouched: it stays flag-gated on `SENTRY_DSN` (Principle 2 above)
and silently no-ops when that env var is unset, same as always.

The reusable workflow `.github/workflows/obs-wire.yml` and the composite action
`.github/actions/obs-wire/action.yml` that used to run the provisioning script are now **deprecated
no-ops**: the `wire` job/step always succeeds immediately, does no network I/O, mints no GitHub App
token, and reads no secret. Their `workflow_call`/`with:` interfaces (`project_slug`, `workers`,
`foundation_ref`, `doppler_token`, `bot_app_id`, `bot_private_key`) are kept byte-identical and marked
deprecated-but-accepted purely for caller compatibility — the ~23 spoke repos that call
`uses: wave-av/wave-foundation/.github/workflows/obs-wire.yml@<SHA>` keep validating without any
caller-side edit, even though the call now does nothing. **No caller action is required**; there is no
urgency to remove the `uses:` line, since it now always succeeds.

If Sentry (or another error-tracking sink) is reinstated, replace this section with fresh provisioning
docs pointing at the new tooling — do not resurrect the deleted scripts by name.

## What this standard intentionally does NOT mandate

- **Distributed tracing / session replay / release health.** Richer Sentry features are opt-in per spoke
  (harvested patterns live in `staging/observability/` and `memories/observability/`). This standard is
  the floor every spoke meets, not the ceiling.
- **A metrics pipeline.** Counters/histograms federate through `api.wave.online`; a spoke does not stand
  up its own Prometheus.

## Source & provenance

This pattern was extracted from `wave-av/private-repo:edge-router/notify.ts` (#25/#26), which has run in
production since 2026-05. The dispatch copy remains the canonical reference for behavior; changes to the
standard land here first, then dispatch and other spokes re-consume.
