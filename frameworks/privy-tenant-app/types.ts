// types.ts
//
// Privy per-tenant app types. Each tenant gets a dedicated Privy app (created in the
// Privy dashboard; not API-creatable as of 2026-06). The wrapper validates app readiness
// + scopes every server-API call to the tenant's (app_id, app_secret) pair so a
// session-token leak in tenant A can never authenticate against tenant B's app.

export type TenantId = string;

export interface ProvisionedPrivyApp {
  tenant_id: TenantId;
  app_id: string;
  /** SHA-256 of app_secret (fingerprint for audit trail — never log the secret itself). */
  app_secret_fingerprint: string;
  /** Echo back of the configured login_methods so callers can persist & detect drift. */
  login_methods: ReadonlyArray<string>;
  verified_at: string;
}

export interface VerifiedPrivyUser {
  /** Privy user id (`did:privy:...`). */
  user_id: string;
  /** Email or wallet-address linked accounts. */
  linked_accounts: Array<{ type: string; address?: string; email?: string }>;
  /** Time the access token was issued (epoch seconds). */
  issued_at: number;
  /** Time the access token expires (epoch seconds). */
  expires_at: number;
}

export type PrivyErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_APP_ID"
  | "INVALID_APP_SECRET"
  | "INVALID_USER_ID"
  | "INVALID_TOKEN"
  | "TOKEN_EXPIRED"
  | "UNAUTHORIZED"
  | "USER_NOT_FOUND"
  | "FETCH_FAILED"
  | "API_ERROR";

export class PrivyError extends Error {
  constructor(
    message: string,
    public readonly code: PrivyErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "PrivyError";
  }
}
