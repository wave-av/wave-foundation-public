# Cloudflare Stream for Platforms

Per-tenant Stream provisioning. WAVE's video core (live + recording + playback) as a platform primitive.

## Pattern

```ts
provisionTenantStream(input) -> { signing_key_id, signing_key_pem }  // once at signup
createTenantUpload(input) -> { uid, upload_url, expires_at }          // per upload
```

## Why signing-key-per-tenant (not API-token-per-tenant)?

CF Stream API tokens require interactive admin:zone consent that doesn't fit auto-provisioning. Instead we:
1. Share WAVE's Stream-scoped API token across tenants.
2. Give each tenant a dedicated **signing key** (for playback URL signing).
3. Tag every upload with `meta.wave_tenant_id`.

Result: tenants can only generate playback URLs signed with their key, and every video in the dataset is queryable by tenant via meta. Their videos are isolated even though the account is shared.

## Usage

```ts
import {
  provisionTenantStream,
  createTenantUpload,
} from "@wave-av/foundation/frameworks/cf-stream-platform";

// At signup:
const stream = await provisionTenantStream({
  tenant_id: "acme",
  cf_account_id: process.env.CF_ACCOUNT_ID!,
  cf_api_token: process.env.CF_STREAM_API_TOKEN!,
});
// Persist stream.signing_key_id + stream.signing_key_pem securely (Doppler tenant-namespace).

// Per upload:
const upload = await createTenantUpload({
  tenant_id: "acme",
  cf_account_id: process.env.CF_ACCOUNT_ID!,
  cf_api_token: process.env.CF_STREAM_API_TOKEN!,
  allowed_origin: "https://acme.example",
  meta: { session_id: "sess_abc" },
});
// Send upload.upload_url to the tenant's client for tus-resumable upload.
```

## Security

- The caller-supplied `meta.wave_tenant_id` is **always overwritten** by the scaffold to prevent
  meta-spoofing.
- Signing keys returned by `provisionTenantStream` MUST be stored encrypted (Doppler / Supabase
  secrets); they grant playback-URL signing for the tenant.
- `cf_api_token` shape validated (≥32 chars); `cf_account_id` validated against 32-hex-char shape.

## Test plan

```bash
npx vitest run frameworks/cf-stream-platform
```

## Refs

- Task #192
- Pairs with A7 cf-calls-platform (interactive video sibling)
- Pairs with A18 cf-custom-domain-tenant (white-label playback URL)
