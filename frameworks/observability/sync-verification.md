# Verifying the Sentry → Linear path end-to-end

A runbook to confirm the observability sinks actually fire — that a real error
reaches **Sentry** and a real report creates a **Linear** issue — using the same
HTTP/GraphQL calls the edge helper (`notify.ts`: `notifyOps`, `createLinearIssue`)
makes. No SDK; just `curl`, so it runs from any shell.

> Phase 5 alerting (`anomaly-routes.yml`) routes `blocking` findings to Linear's
> SECURITY team via exactly this path — so this verification doubles as the Phase-5
> alerting smoke test.

## Preconditions

Export the same env the spoke uses (from its secret store — never paste secrets into
a shared shell history; prefer a subshell):

```bash
# Sentry: DSN is https://<public_key>@<host>/<project_id>
export SENTRY_DSN='https://<public_key>@<host>/<project_id>'
# Linear: a personal/integration API key + the target team id
export LINEAR_API_KEY='lin_api_...'
export LINEAR_TEAM_ID='<uuid>'   # the SECURITY team for the Phase-5 path
```

This creates a **real** Sentry event and a **real** Linear issue. Both are tagged
`sync-verification` so you can find + delete them after. Do it in a non-prod project
if you have one; if you must use prod, clean up (step 4).

## 1 — Sentry: fire a test event

Derive the ingest endpoint from the DSN (`https://<host>/api/<project_id>/store/`,
auth via `sentry_key=<public_key>` — the public key is a client ingest key, safe to use):

```bash
host=$(printf '%s' "$SENTRY_DSN" | sed -E 's#https://[^@]+@([^/]+)/.*#\1#')
pubkey=$(printf '%s' "$SENTRY_DSN" | sed -E 's#https://([^@]+)@.*#\1#')
projid=$(printf '%s' "$SENTRY_DSN" | sed -E 's#.*/([0-9]+)$#\1#')

curl -sS "https://$host/api/$projid/store/" \
  -H "Content-Type: application/json" \
  -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=$pubkey" \
  -d '{"message":"sync-verification test event","level":"error","tags":{"verification":"sync-verification"}}'
# → {"id":"<event_id>"}
```

**Expect:** a JSON `id`, and within ~30s the event in Sentry under the project,
tagged `verification:sync-verification`. If you get `403`/`401`, the DSN/key is wrong;
if nothing appears, the project_id is wrong.

## 2 — Linear: create a test issue (the `createLinearIssue` call)

```bash
curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c '
import json, os
q = "mutation($t:String!,$d:String!,$team:String!){issueCreate(input:{title:$t,description:$d,teamId:$team}){success issue{id identifier url}}}"
print(json.dumps({"query": q, "variables": {
  "t": "[sync-verification] observability path test",
  "d": "Created by frameworks/observability/sync-verification.md. Safe to delete.",
  "team": os.environ["LINEAR_TEAM_ID"]}}))
')"
# → {"data":{"issueCreate":{"success":true,"issue":{"identifier":"SEC-123","url":"..."}}}}
```

**Expect:** `success: true` + an `identifier`/`url`. `success:false` or an `errors`
array → the `LINEAR_API_KEY` lacks scope or `LINEAR_TEAM_ID` is wrong (a common
miss: the key's workspace doesn't contain that team).

## 3 — Confirm the routing contract

- The finding/feedback severity that should reach Linear is `blocking` (Phase 5) or a
  `bug` report (`forwardFeedback`). Confirm your caller passes that severity — a
  `warning` deliberately goes to Sentry only (see `anomaly-routes.yml`).
- `forwardFeedback` returns the attempted sinks (`["linear","alert"]`); assert that
  list in the route's response/log so a silently-dropped sink is visible.

## 4 — Cleanup

```bash
# Delete the Linear test issue (use the id from step 2):
curl -sS https://api.linear.app/graphql -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation($id:String!){issueDelete(id:$id){success}}","variables":{"id":"<issue_id>"}}'
# Sentry test events age out; or resolve/delete the issue in the UI by the sync-verification tag.
```

## Pass criteria

- [ ] Sentry returns an event id; the event shows up tagged `sync-verification`.
- [ ] Linear `issueCreate.success == true` with an identifier in the **expected team**.
- [ ] The caller's sink list includes the sink you expected for that severity.
- [ ] Test artifacts cleaned up.

## When it fails

| Symptom | Cause |
|---------|-------|
| Sentry `403`/`401` | wrong public key / DSN |
| Sentry 200 but no event | wrong `project_id` in the DSN |
| Linear `success:false` | key lacks scope, or `LINEAR_TEAM_ID` not in the key's workspace |
| Linear issue lands in the wrong team | `LINEAR_TEAM_ID` points at the default team, not SECURITY (Phase-5 routes to SECURITY) |
| Nothing forwarded at runtime | sink env unset → no-op by design (flag-gated off); set the env in the spoke's secret store |
