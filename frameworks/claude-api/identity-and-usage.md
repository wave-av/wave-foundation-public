# Identity & Per-User Usage

> Every Anthropic call must be **attributable to a single principal** and authenticated by a
> **short-lived, ephemeral** credential — no static `sk-ant-api...` secret in the runtime. This is the
> fix for the secret-hygiene root cause (cleartext prod tokens in 34+ files). The model-routing
> gateway tier is the single **identity / attribution point**; it spins up a per-user token, stamps
> the principal, and aggregates `usage_report`/`cost_report` back to it.
>
> Two audiences, one mechanism:
> - **US** — internal humans + agents + bots (one service account per workload class).
> - **OUR USERS** — customer-facing tenants (one workspace per tenant for spend caps + attribution).

## The one rule

**Runtime credential = short-lived bearer token from `POST /v1/oauth/token`.** A static Admin/API key
is a *fallback only*, Doppler-injected and rotated — never the default, never committed. The gateway
mints the per-user token; call sites never see `sk-ant-api...`.

## Mechanism tiers (most → least preferred)

| Tier | Credential | Header | Attribution unit | Use for |
|------|-----------|--------|------------------|---------|
| **1. WIF per-user token** | `sk-ant-oat01-...` exchanged at `POST /v1/oauth/token` | `Authorization: Bearer` | `service_account_id` (+ `workspace_id`) | DEFAULT — all internal + agent traffic |
| **2. Workspace + scoped key** | static key bound to a tenant workspace | `x-api-key` | `workspace_id` + `api_key_id` | per-USER tenants needing spend caps |
| **3. Static Admin/API key** | `sk-ant-api...` / `sk-ant-admin...` | `x-api-key` | `api_key_id` only | FALLBACK; Doppler-injected, rotated |

WIF removes the static secret entirely: there is "no `sk-ant-api...` string to mint, distribute, or
rotate" (`authentication.md`). Tokens expire in minutes; a leak's blast radius is the token lifetime.

## How the exchange works (WIF)

1. The workload's IdP issues a signed JWT (ambient on the platform: K8s projected SA token, GHA OIDC,
   GCP metadata, AWS STS web-identity). `iss` identifies the provider; `sub`/claims identify the workload.
2. The gateway posts the JWT to `POST /v1/oauth/token` using the RFC 7523 `jwt-bearer` grant. Anthropic
   verifies the signature against the registered JWKS, checks `exp`/`nbf`/`iat`, matches the JWT against
   the **federation rule** (`fdrl_...`), and returns a short-lived `sk-ant-oat01-...` acting as the
   target **service account** (`svac_...`).
3. The SDK (or gateway) caches the token and refreshes before expiry — advisory at exp−120s, mandatory
   at exp−30s. It re-reads the token file each exchange, so rotated projected tokens are picked up.

Three Console resources, one sentence: *"tokens signed by issuer X, with claims like Y, may act as
service account Z."* — **federation issuer** (`fdis_...`) + **federation rule** (`fdrl_...`) + **service
account** (`svac_...`). One issuer per environment (prod EKS / staging / GHA = three issuers). One rule
per team/namespace/permission level. Rules are evaluated **by ID** — the client names the rule; there
is no implicit search.

```bash
# Exchange IdP JWT -> short-lived Anthropic token (gateway does this; shown for debugging)
JWT=$(cat /var/run/secrets/anthropic.com/token)
RESPONSE=$(curl -sS https://api.anthropic.com/v1/oauth/token \
  -H "content-type: application/json" \
  --data @- <<JSON
{
  "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
  "assertion": "$JWT",
  "federation_rule_id": "fdrl_...",
  "organization_id": "00000000-0000-0000-0000-000000000000",
  "service_account_id": "svac_...",
  "workspace_id": "wrkspc_..."
}
JSON
)
ACCESS_TOKEN=$(jq -r .access_token <<<"$RESPONSE")   # sk-ant-oat01-...
EXPIRES_IN=$(jq -r .expires_in   <<<"$RESPONSE")     # re-exchange before this elapses

# Then call with Authorization: Bearer (NOT x-api-key)
curl -sS https://api.anthropic.com/v1/messages \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d '{"model":"claude-opus-4-8","max_tokens":1024,"messages":[{"role":"user","content":"hi"}]}'
```

```python
# Zero-arg client: ship one image everywhere, inject env per environment.
# Resolves WorkloadIdentityCredentials from ANTHROPIC_FEDERATION_RULE_ID /
# ANTHROPIC_ORGANIZATION_ID / ANTHROPIC_SERVICE_ACCOUNT_ID / ANTHROPIC_WORKSPACE_ID /
# ANTHROPIC_IDENTITY_TOKEN_FILE. Never route this directly — point ANTHROPIC_BASE_URL at the gateway.
from anthropic import Anthropic
client = Anthropic()  # no api_key; SDK runs the exchange + refresh loop
```

### Credential precedence — the silent-shadow trap

SDKs resolve in five tiers: constructor args → `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN` → explicit
`ANTHROPIC_PROFILE` → federation env vars → active profile. **`ANTHROPIC_API_KEY` sits ABOVE
federation** — a leftover key silently shadows WIF. When migrating: confirm `ANTHROPIC_API_KEY` is
unset in container env, CI secrets, AND shell profiles; verify with `ant auth status`; then revoke the
key in Console. This is the exact secret-hygiene failure mode we are eliminating.

## Attribution: usage_report & cost_report

Per-principal usage is read from the Admin API. Group by the unit that matches the audience.

| Endpoint | group_by axes | Best attribution unit |
|----------|---------------|-----------------------|
| `GET /v1/organizations/usage_report/messages` | `api_key_id`, `workspace_id`, `model`, `service_tier`, `context_window`, `inference_geo`, `speed`, `account_id`, `service_account_id` | **per US agent** → `service_account_id`; **per USER** → `workspace_id` |
| `GET /v1/organizations/cost_report` | `workspace_id`, `description` | **$ per USER tenant** → `workspace_id` |

Load-bearing nuances from the snapshot:
- `usage_report` result rows carry `service_account_id` (null for non-OIDC-federation) and `account_id`
  (null for non-OAuth) — so **WIF tokens are the only credential that gives clean per-service-account
  attribution.** A static key only yields `api_key_id`.
- Filter narrow with `account_ids[]`, `api_key_ids[]`, `service_account_ids[]`, `workspace_ids[]`.
- `cost_report` `bucket_width` is **`1d` only**; `usage_report` supports `1m`/`1h`/`1d` (limits:
  1d→7/max31, 1h→24/max168, 1m→60/max1440). `amount` is a decimal string in cents.
- Cache attribution lands in `usage.cache_read_input_tokens` + `cache_creation.ephemeral_{5m,1h}_input_tokens`
  per row — confirm cache hits here, and bill read at 0.1x, 5m-write 1.25x, 1h-write 2x.

```bash
# $ per customer tenant, last 7 days
curl https://api.anthropic.com/v1/organizations/cost_report \
  -H 'anthropic-version: 2023-06-01' -H "x-api-key: $ANTHROPIC_ADMIN_API_KEY" \
  --data-urlencode 'starting_at=2026-05-23T00:00:00Z' --data-urlencode 'group_by[]=workspace_id' -G
```

## Workspace-per-tenant (the USER audience)

A workspace is the spend-cap + attribution boundary. `POST /v1/organizations/workspaces` per customer
tenant; a WIF rule (or scoped key) targets that workspace, and the minted token "follows that
workspace's rate limits and usage attribution, the same as an API key." Set `data_residency`
(`workspace_geo` is **immutable after creation**) and `tags` (keys must not start with `anthropic`) at
creation. A service account becomes active in a workspace only once added to its Members.

## ZDR & batch interaction (attribution ≠ retention)

- **Prompt caching IS ZDR-eligible** — prompts/outputs not stored; KV + hashes held in memory for the
  TTL only. Safe to keep on for ZDR tenants.
- **Batch API is NOT ZDR-eligible** (29-day async storage) and gives 50% off. Never route a ZDR
  tenant's traffic through `/v1/messages/batches`; gate batch behind a per-workspace ZDR flag.
- Files API, code execution, MCP connector, skills are also **not** ZDR-eligible — same gate.

## Anti-patterns

- ❌ Static `sk-ant-api...` in code, `.env`, or any committed file (the root-cause bug).
- ❌ Leaving `ANTHROPIC_API_KEY` set in a WIF workload — it silently shadows federation.
- ❌ Calling `api.anthropic.com` directly with a per-user token — bypasses the gateway, loses
  aggregation; the gateway IS the attribution point (`frameworks/model-routing`).
- ❌ Sharing one workspace/service account across tenants — collapses per-USER attribution.
- ❌ Sending a per-user OAuth token in `x-api-key` (it goes in `Authorization: Bearer`).
- ❌ Routing ZDR-tenant traffic through Batch to save 50% (Batch is not ZDR-eligible).
- ❌ Date-suffixing a model alias — use the exact string `claude-opus-4-8`.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_FEDERATION_RULE_ID` | `fdrl_...` — names the WIF rule (tier 1) |
| `ANTHROPIC_ORGANIZATION_ID` | org UUID for the exchange |
| `ANTHROPIC_SERVICE_ACCOUNT_ID` | `svac_...` — the principal a WIF token acts as |
| `ANTHROPIC_WORKSPACE_ID` | `wrkspc_...` — tenant/spend-cap boundary |
| `ANTHROPIC_IDENTITY_TOKEN_FILE` | path to the IdP JWT (re-read each exchange) |
| `ANTHROPIC_ADMIN_API_KEY` | `sk-ant-admin...` for usage/cost reports (Doppler-injected, rotated) |
| `ANTHROPIC_API_KEY` | tier-3 FALLBACK ONLY; MUST be unset in WIF workloads (shadows federation) |
| `ANTHROPIC_BASE_URL` | points at the gateway/shim — never `api.anthropic.com` |

## WAVE binding

- All Anthropic traffic egresses through the model-routing **Leveragizer**
  (`local → gateway → openrouter → direct → human`); the gateway tier mints the per-user WIF token and
  is the attribution chokepoint. Never bypass it for direct Anthropic.
- Never hardcode a model in code — route via config (default `claude-opus-4-8`).
- Static keys, where unavoidable (tier 3), are Doppler-injected and on the rotation schedule; treat any
  committed `sk-ant-*` as leaked → rotate immediately.
- Build tasks: per-user WIF provisioning + attribution in wave-gateway (#19); usage/cost → Leveragizer
  budgets + 80%/100% alerts (#20).

## Related

- [`gateway-integration.md`](./gateway-integration.md) — the egress seam; who rewrites what, in what order.
- [`frameworks/model-routing/README.md`](../model-routing/README.md) — five-tier escalation + budget caps.
- [`frameworks/secrets-management`](../secrets-management/) — Doppler injection + rotation for tier-3 keys.

---

Sources (snapshot, 2026-05-30): `manage-claude/authentication.md`,
`manage-claude/workload-identity-federation.md`, `manage-claude/api-and-data-retention.md`,
`api/admin/usage_report.md`, `api/admin/cost_report.md`, `api/admin/api_keys.md`,
`api/admin/workspaces.md`.
