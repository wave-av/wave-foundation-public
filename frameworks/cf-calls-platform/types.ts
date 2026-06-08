// Shared types for Cloudflare Calls per-tenant (WebRTC).
// CF Calls = interactive WebRTC primitive. For for-Platforms each tenant gets:
//   - their own Calls App (org-isolated)
//   - per-session TURN credentials
// This sits next to A6 cf-stream-platform (which is broadcast-side).

export type TenantId = string;

export interface ProvisionedCallsApp {
  tenant_id: TenantId;
  cf_app_id: string;
  cf_app_secret: string;          // returned ONCE at create — store encrypted
  cf_account_id: string;
  created_at: string;
}

export interface TurnCredential {
  tenant_id: TenantId;
  cf_app_id: string;
  ice_servers: Array<{ urls: string | string[]; username?: string; credential?: string }>;
  expires_at: string;
}

export class CallsPlatformError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "CallsPlatformError";
  }
}
