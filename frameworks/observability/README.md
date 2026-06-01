# WAVE Observability Standard

> How every WAVE spoke reports errors, raises ops alerts, and routes user feedback — one pattern,
> consumed not copied. Reference implementation: [`scaffolder/templates/observability/notify.ts`](../../scaffolder/templates/observability/notify.ts),
> proven in prod as `wave-av/wave-dispatch:edge-router/notify.ts`.

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
ones with `mcp sentry create_project` (or the dashboard); store the returned DSN as `SENTRY_DSN` in that
spoke's secret store — **never commit it into the repo**.

| Spoke / system | Sentry project slug | Notes |
|----------------|---------------------|-------|
| wave-dispatch | `wave-dispatch` | edge-router Worker — live wiring via `edge-router/notify.ts` |
| wave-surfer-connect | `wave-surfer-connect` | Next.js hub (`api.wave.online`) |
| wave-foundation | `wave-foundation` | chassis tooling / consumer-smoke |
| wave-moq-edge | `wave-moq-edge` | MoQ media edge |
| wave-ai-cloud | `wave-ai-cloud` | Mac Studio AI platform / router infra |
| claude-protocol-suite | `claude-protocol-suite` | skills / agent tooling |
| burnrate | `burnrate` | Electron desktop app |

> DSNs themselves live in each spoke's secret manager + the operator's local manifest, not here. This
> table is the authoritative **map of which project belongs to which spoke** so a new spoke doesn't
> create a duplicate or report into the wrong project.

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
