# Cloudflare Calls for Platforms

Per-tenant Cloudflare Calls (WebRTC) provisioning. Interactive video sibling to A6 `cf-stream-platform` (broadcast).

## Pattern

```ts
provisionTenantCallsApp(input) -> { cf_app_id, cf_app_secret }  // once at signup
issueTenantTurnCredential(input) -> { ice_servers, expires_at }  // per session
```

## Why per-app (not session-tagging on a shared app)?

CF Calls Apps isolate sessions, TURN credentials, and metrics by design. A shared app forces every tenant's sessions through the same metrics namespace and shares the secret. Per-tenant app means:
- isolated TURN traffic accounting
- secret-rotation per tenant (no global rotation event)
- compromised tenant doesn't read others' SDP offers

## Usage

```ts
import {
  provisionTenantCallsApp,
  issueTenantTurnCredential,
} from "@wave-av/foundation/frameworks/cf-calls-platform";

// On signup:
const app = await provisionTenantCallsApp({
  tenant_id: "acme",
  cf_account_id: env.CF_ACCOUNT_ID,
  cf_api_token: env.CF_CALLS_API_TOKEN,
});
// Persist app.cf_app_id + app.cf_app_secret encrypted (Doppler tenant-namespace).

// Per session:
const cred = await issueTenantTurnCredential({
  tenant_id: "acme",
  cf_app_id: app.cf_app_id,
  cf_app_secret: app.cf_app_secret,
  ttl_seconds: 3600,
});
// Send cred.ice_servers to the tenant's client for RTCPeerConnection.
```

## Security

- App secret returned ONCE at create — caller must store encrypted immediately.
- TTL bounded `[60, 86400]` seconds (1m – 24h).
- App-id + secret length checks; account-id 32-hex check; token length check.
- Validation runs before any network call.

## Test plan

```bash
npx vitest run frameworks/cf-calls-platform
```

## Refs

- Task #193
- Pairs with A6 cf-stream-platform (broadcast sibling)
- Pairs with A8/A9 cf-kv/cf-do (session state primitives)
