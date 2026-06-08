// types.ts
//
// Cloudflare Custom Hostnames (SSL-for-SaaS) per-tenant types. Tenants point their own
// hostname (e.g. app.acme.com) at WAVE; CF provisions a cert and binds the hostname to
// our zone so traffic routes to a tenant-specific Worker.

export type TenantId = string;

export type ValidationMethod = "http" | "txt" | "email";
export type HostnameStatus =
  | "pending_validation"
  | "active"
  | "active_redeploying"
  | "validation_timed_out"
  | "blocked"
  | "moved"
  | "deleted";

export interface ProvisionedCustomHostname {
  tenant_id: TenantId;
  hostname: string;
  cf_hostname_id: string;
  status: HostnameStatus;
  validation_method: ValidationMethod;
  /** Ownership challenge the tenant must add to their DNS. Present when status=pending_validation. */
  ownership_challenge: {
    name: string;
    value: string;
    type: "TXT";
  } | null;
  date_created: string;
}

export type CustomDomainErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_HOSTNAME"
  | "INVALID_ACCOUNT_ID"
  | "INVALID_ZONE_ID"
  | "INVALID_API_TOKEN"
  | "RESERVED_HOSTNAME"
  | "INVALID_VALIDATION_METHOD"
  | "UNAUTHORIZED"
  | "HOSTNAME_EXISTS"
  | "FETCH_FAILED"
  | "API_ERROR";

export class CustomDomainError extends Error {
  constructor(
    message: string,
    public readonly code: CustomDomainErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "CustomDomainError";
  }
}
