# Admin API

The **Admin API** (`/v1/organizations/*`) is the ops/control plane for an Anthropic org: API keys, usage + cost telemetry, rate limits, workspaces, members, invites/users/orgs, and MCP tunnels. It is **how WAVE attributes spend, feeds the Leveragizer budget caps, and provisions short-lived identities** — not a path for serving inference. For the data-plane attribution side (per-user WIF tokens, `metadata.user_id`, `usage.*`), see [`identity-and-usage.md`](./identity-and-usage.md).

## Distinct admin key — non-negotiable

Every endpoint here authenticates with a **separate Admin API key** (`sk-ant-admin...`), passed as `X-Api-Key: $ANTHROPIC_ADMIN_API_KEY`. A normal inference key (`sk-ant-api...`) returns 401 on these routes, and vice-versa. The admin key:

- Is **org-scoped, never put in a spoke or client**. It lives in the Vercel `wave` pantry, pulled by the gateway/ops jobs only.
- Is the credential a leak would let an attacker rotate every key + read every dollar of spend. Treat it like the Stripe secret.
- Is **not** the path for serving models — it cannot call `/v1/messages`. Route inference through the gateway (Leveragizer tier 2), never the admin key.

## Endpoint map

| Resource | Method + path | Use |
|----------|---------------|-----|
| API keys | `GET /api_keys`, `GET /api_keys/{id}`, `POST /api_keys/{id}` | List / inspect / update (name + `status`) — **no create or hard-delete via API** |
| Usage report | `GET /usage_report/messages`, `GET /usage_report/claude_code` | Token usage by bucket; `group_by[]` for per-key/workspace/model |
| Cost report | `GET /cost_report` | Dollar cost by `1d` bucket; `group_by[]=workspace_id,description` |
| Rate limits (org) | `GET /rate_limits` | Per model-group + API-surface limiter values |
| Rate limits (ws) | `GET /workspaces/{id}/rate_limits` | Same, scoped to one workspace |
| Workspaces | `POST /workspaces`, `GET …`, `POST …`, `POST …/archive` | CRUD + archive (no hard delete; `data_residency` immutable `workspace_geo`) |
| Members | `POST/GET/POST/DELETE /workspaces/{id}/members[/{user_id}]` | Add / get / list / update role / remove |
| Invites | `POST/GET/DELETE /invites[/{id}]`, `GET /invites` | Invite by email + role; delete pending |
| Users | `GET/POST/DELETE /users/{id}`, `GET /users` | Get / update role / remove / list |
| Organization | `GET /organizations/me` | Resolve org id + name for the active key |
| MCP tunnels | `GET /tunnels`, reveal/rotate token, archive, certs | Private MCP server routing (**beta header required**) |

All list endpoints are cursor-paginated (`after_id`/`before_id` or opaque `page`/`next_page`, `has_more`). `limit` defaults 20, max 1000.

## API keys (`/api_keys`)

`APIKey` = `{ id, created_at, created_by{id,type}, expires_at, name, partial_key_hint, status, type:"api_key", workspace_id }`. `status` ∈ `active|inactive|archived|expired`.

The **secret value is never returned** — only `partial_key_hint` (e.g. `sk-ant-api03-R2D...igAA`). Keys are minted in the Console; the API can only **list/get/update**. "Rotate" = `POST /api_keys/{id}` to set `status:"inactive"`/`"archived"` on the old key after the replacement is live. Filter list by `status`, `workspace_id`, `created_by_user_id`.

```python
import os, anthropic
client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_ADMIN_API_KEY"])

# Disable a key (rotation step 2 — after the new key is deployed)
client.beta.messages  # inference client; admin lives on client.organizations / raw HTTP
```

```bash
# List active keys for one workspace
curl "https://api.anthropic.com/v1/organizations/api_keys?status=active&workspace_id=$WS" \
  -H 'anthropic-version: 2023-06-01' -H "X-Api-Key: $ANTHROPIC_ADMIN_API_KEY"

# Rotate: archive the old key once the replacement is verified live
curl "https://api.anthropic.com/v1/organizations/api_keys/$OLD_KEY_ID" \
  -H 'Content-Type: application/json' -H 'anthropic-version: 2023-06-01' \
  -H "X-Api-Key: $ANTHROPIC_ADMIN_API_KEY" -d '{"status":"archived"}'
```

## Usage report (`/usage_report/messages`)

The spend-attribution feed for the Leveragizer. Returns time buckets (`bucket_width` ∈ `1m|1h|1d`) each holding `results[]`. Group with `group_by[]` (subset of `api_key_id`, `workspace_id`, `model`, `service_tier`, `context_window`, `inference_geo`, `account_id`, `service_account_id`, `speed`). Filter with `api_key_ids[]`, `workspace_ids[]`, `account_ids[]`, `models[]`, `context_window[]` (`0-200k`/`200k-1M`), `service_tiers[]`, etc.

Per-result token fields — **the canonical numbers for cache-hit verification**:

| Field | Meaning |
|-------|---------|
| `uncached_input_tokens` | Input not served from cache |
| `cache_read_input_tokens` | Cache hits (priced **0.1×**) — see [`prompt-caching.md`](./prompt-caching.md) |
| `cache_creation.ephemeral_5m_input_tokens` | 5m write (**1.25×**) |
| `cache_creation.ephemeral_1h_input_tokens` | 1h write (**2×**) |
| `output_tokens` | Generated |
| `server_tool_use.web_search_requests` | Server-tool count |

`service_tier` ∈ `standard|batch|priority|priority_on_demand|flex|flex_discount`. **`batch` rows are the 50%-off Batch API** ([`batch.md`](./batch.md)) — they are NOT ZDR-eligible; prompt caching IS. `group_by[]=speed` needs the `fast-mode-2026-02-01` beta header.

`/usage_report/claude_code` is a **separate daily report** (single `starting_at` day, `YYYY-MM-DD`): per-actor commits/PRs/LOC/sessions + `model_breakdown[].estimated_cost` + tool accept/reject — for dev-productivity dashboards, not billing.

```bash
# Daily spend by API key + model — the budget-cap input
curl -G "https://api.anthropic.com/v1/organizations/usage_report/messages" \
  --data-urlencode "starting_at=2026-05-23T00:00:00Z" \
  --data-urlencode "bucket_width=1d" \
  --data-urlencode "group_by[]=api_key_id" --data-urlencode "group_by[]=model" \
  -H 'anthropic-version: 2023-06-01' -H "X-Api-Key: $ANTHROPIC_ADMIN_API_KEY"
```

## Cost report (`/cost_report`)

Actual dollars (not tokens). `bucket_width` is **`1d` only**. `group_by[]` ∈ `workspace_id`, `description`. Each result: `amount` (decimal string, **lowest currency unit — cents**; `"123.45"` = $1.23), `currency` (always `USD`), `cost_type` ∈ `tokens|web_search|code_execution|session_usage`, `token_type`, `model`, `service_tier` ∈ `standard|batch`, `context_window`, `inference_geo`, `description`.

Use `cost_report` for $ caps + finance; use `usage_report` for token mechanics (cache ratios, tier mix). Cross-check: a high `cache_read_input_tokens` share in usage should track a lower `amount` in cost.

## Rate limits (`/rate_limits`)

Read-only. One entry per group: `group_type` ∈ `model_group|batch|token_count|files|skills|web_search`; `models[]` populated only for `model_group` (incl. aliases, else `null`); `limits[]` = `{type, value}` where `type` is e.g. `requests_per_minute`, `input_tokens_per_minute`. Filter by `group_type` or `model` (full names + aliases; 404 if no limit). Workspace-scoped variant: `GET /workspaces/{id}/rate_limits`. Feed these into the Leveragizer's tier-2 throttle so the gateway backs off **before** Anthropic 429s.

## Workspaces, members, invites, users, org

- **Workspaces** — `POST` create (`name`, optional `data_residency{workspace_geo (immutable), allowed_inference_geos|"unrestricted", default_inference_geo}`, `tags` map — keys can't start with `anthropic`). Get/list/update; **`/archive` instead of delete** (`archived_at` set). Default geo = `workspace_geo:"us"`, `allowed:"unrestricted"`, `default:"global"`.
- **Members** — `WorkspaceMember{type, user_id, workspace_id, workspace_role}`. `workspace_role` ∈ `workspace_user|workspace_developer|workspace_restricted_developer|workspace_admin`; **`workspace_billing` is read-only — cannot be set via create/update**. CRUD = create/get/list/update-role/delete.
- **Invites** — `POST` with `email` + `role` ∈ `user|developer|billing|claude_code_user` (**never `admin`**). `Invite{id,email,expires_at,invited_at,role,status,type}`; `status` ∈ `pending|accepted|expired|deleted`. `DELETE` a pending invite → `invite_deleted`.
- **Users** — `User{id,added_at,email,name,role,type}`; same role enum (update **cannot set `admin`**). Get/list (filter by `email`)/update-role/remove (`user_deleted`).
- **Organization** — `GET /organizations/me` → `{id,name,type:"organization"}`; the only org endpoint, used to resolve the active key's org.

## MCP tunnels (`/tunnels`) — beta

Private routing for self-hosted MCP servers. **Every tunnel endpoint requires** `anthropic-beta: mcp-tunnels-2026-05-19`. `Tunnel{id,archived_at,created_at,display_name,domain,type,workspace_id}` — `domain` is an Anthropic-assigned hostname, globally unique and never reused. Endpoints: `GET` get/list, `POST …/reveal_token`, `POST …/rotate_token`, `POST …/archive`, plus certificate CRUD (`…/certificates`).

- `reveal_token` is `POST` (keeps the token out of access logs); the value is fetched live, **never stored by Anthropic**, and stable until rotated.
- `rotate_token` issues a fresh token and invalidates the old one for **new** connections; existing connections persist until the connector restarts. Pass an optional `reason`.
- Snapshot examples authenticate tunnels with `Authorization: Bearer $ANTHROPIC_WIF_BEARER_TOKEN` (WIF) — the same short-lived-token posture WAVE prefers everywhere.

## WAVE integration

- Admin key lives in the Vercel `wave` pantry only; the gateway/ops jobs pull it. Never ship it to a spoke or client.
- `usage_report` (tokens) + `cost_report` (dollars) are the **inputs to the Leveragizer budget caps** ([`../model-routing/README.md`](../model-routing/README.md)): per-tenant daily cap enforced at the gateway, per-app monthly cap → Slack at 80%, hard stop at 100% unless overridden. Cross-feed into Sentry/Linear via the observability standard.
- Attribute per actor via `group_by[]=account_id|api_key_id|workspace_id`. For human↔agent↔delegate attribution on the data plane, mint **short-lived WIF / OIDC-federated tokens** (`service_account_id` surfaces in usage) — see [`identity-and-usage.md`](./identity-and-usage.md).
- Mirror `rate_limits` into the gateway throttle so tier 2 backs off before a 429 escalates to tier 3.

## Anti-patterns

- ❌ **Minting long-lived per-user inference keys** when WIF / OIDC short-lived tokens suffice. Long-lived keys are unrotatable-at-scale, leak-prone, and lose per-actor `service_account_id` attribution. Federate identity; mint keys only for machine principals that genuinely can't do WIF.
- ❌ Putting the **Admin key in a spoke, client, or `/v1/messages` call** — it's org-scoped control plane, not an inference credential.
- ❌ Treating `usage_report` numbers as dollars (they're tokens) or `cost_report` `amount` as dollars (it's **cents**, decimal string).
- ❌ Hard-deleting keys/workspaces — there is no destructive delete; you **archive** (keys → `status`, workspaces → `/archive`). Don't assume an ID is gone.
- ❌ Polling `usage_report` at `1m` for billing — use `1d` cost buckets; reserve `1m`/`1h` for live spike detection.
- ❌ Calling tunnel endpoints without the `mcp-tunnels-2026-05-19` beta header (every one 400s otherwise), or storing a revealed `tunnel_token` long-term instead of re-revealing.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_ADMIN_API_KEY` | Admin key (`sk-ant-admin…`); `X-Api-Key` for all `/v1/organizations/*` |
| `ANTHROPIC_WIF_BEARER_TOKEN` | Short-lived WIF bearer for tunnel + federated calls (preferred over long-lived keys) |
| `ANTHROPIC_ORG_ID` | Cache of `GET /organizations/me` for log/metric tagging |

## Sources

- `SNAP/api/admin/api_keys.md`
- `SNAP/api/admin/usage_report.md`
- `SNAP/api/admin/cost_report.md`
- `SNAP/api/admin/rate_limits.md`
- `SNAP/api/admin/workspaces.md`
- `SNAP/api/admin/invites.md`
- `SNAP/api/admin/users.md`
- `SNAP/api/admin/organizations.md`
- `SNAP/api/admin/mcp_tunnels.md`
