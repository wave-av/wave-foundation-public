// Shared types for Cloudflare Stream per-tenant.
// CF Stream is WAVE's video core (live + recording + playback). For for-Platforms, each
// tenant gets API-token-scoped Stream access + their videos tagged with `tenant_id`.

export type TenantId = string;

export interface ProvisionedStreamTenant {
  tenant_id: TenantId;
  cf_api_token_id: string;       // CF API token ID, scoped to Stream + this tenant's videos
  cf_account_id: string;
  signing_key_id?: string;       // optional: for signed-URL playback
  signing_key_pem?: string;      // private key, PEM-format (only returned at creation)
  created_at: string;
}

export interface StreamUpload {
  uid: string;                   // CF Stream UID
  upload_url: string;            // tus-resumable URL the customer uploads to
  expires_at: string;
}

export class StreamPlatformError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "StreamPlatformError";
  }
}
