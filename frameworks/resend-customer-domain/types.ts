// Shared types for the Resend per-tenant domain scaffold.
// Each WAVE tenant gets `mail.<tenant_id>.<base_domain>` as their own sending domain,
// with per-tenant DKIM + SPF (so deliverability and reputation are isolated).

export type TenantId = string;

export interface ProvisionedDomain {
  tenant_id: TenantId;
  resend_domain_id: string; // dom_…
  sending_domain: string;   // e.g. mail.acme.wave.online
  dns_records: DnsRecord[]; // operator/tenant must publish these in their zone
  status: "pending" | "verified" | "failed";
  created_at: string; // ISO
}

export interface DnsRecord {
  type: "MX" | "TXT" | "CNAME";
  name: string;
  value: string;
  priority?: number; // MX only
  ttl?: number;
}

export class ResendDomainError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "ResendDomainError";
  }
}
