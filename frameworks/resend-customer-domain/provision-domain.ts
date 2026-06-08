// provision-domain.ts
//
// One-call provisioning of a per-tenant sending domain on Resend.
// Returns the DKIM/SPF DNS records the operator must publish before the domain can verify.
//
// Caller responsibilities:
//   - Pass the WAVE tenant_id (slug, ^[a-zA-Z0-9_-]{1,64}$) and the base domain WAVE owns.
//   - Publish the returned `dns_records` in the appropriate zone (operator-owned base zone, or
//     a per-tenant zone if A18 cf-custom-domain-tenant is also in play).
//   - Persist `resend_domain_id` next to the tenant record (Supabase/Doppler per for-Platforms).

import { DnsRecord, ProvisionedDomain, ResendDomainError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const BASE_DOMAIN_REGEX = /^([a-z0-9-]+\.)+[a-z]{2,}$/i;
const RESEND_API_BASE = "https://api.resend.com";

export interface ProvisionInput {
  tenant_id: TenantId;
  /** Base domain WAVE owns. We create `mail.<tenant>.<base>`. e.g. "wave.online". */
  base_domain: string;
  /** Optional subdomain prefix (default "mail"). */
  subdomain?: string;
  /** Optional region hint for Resend region selection. */
  region?: "us-east-1" | "eu-west-1" | "sa-east-1" | "ap-northeast-1";
}

export async function provisionTenantDomain(
  resendApiKey: string,
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedDomain> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new ResendDomainError(
      `invalid tenant_id: must match ${TENANT_ID_REGEX}`,
      "INVALID_TENANT_ID",
    );
  }
  if (!BASE_DOMAIN_REGEX.test(input.base_domain)) {
    throw new ResendDomainError("invalid base_domain", "INVALID_BASE_DOMAIN");
  }
  if (!resendApiKey || !resendApiKey.startsWith("re_")) {
    throw new ResendDomainError("invalid resend api key shape", "INVALID_API_KEY");
  }

  const subdomain = input.subdomain ?? "mail";
  if (!/^[a-z0-9-]{1,32}$/.test(subdomain)) {
    throw new ResendDomainError("invalid subdomain", "INVALID_SUBDOMAIN");
  }

  const sending_domain = `${subdomain}.${input.tenant_id}.${input.base_domain}`;

  let res: Response;
  try {
    res = await fetchImpl(`${RESEND_API_BASE}/domains`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name: sending_domain,
        region: input.region ?? "us-east-1",
      }),
    });
  } catch (err) {
    throw new ResendDomainError("resend api fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    const text = await safeText(res);
    throw new ResendDomainError(
      `resend api ${res.status}: ${text}`,
      res.status === 422 ? "DOMAIN_CONFLICT" : "API_ERROR",
    );
  }

  let body: any;
  try {
    body = await res.json();
  } catch (err) {
    throw new ResendDomainError("resend api returned non-json", "INVALID_RESPONSE", err);
  }

  const dns_records: DnsRecord[] = (body.records ?? []).map((r: any) => ({
    type: r.type,
    name: r.name,
    value: r.value,
    priority: r.priority,
    ttl: r.ttl,
  }));

  return {
    tenant_id: input.tenant_id,
    resend_domain_id: body.id,
    sending_domain,
    dns_records,
    status: (body.status ?? "pending") as ProvisionedDomain["status"],
    created_at: new Date().toISOString(),
  };
}

async function safeText(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 500);
  } catch {
    return "<unreadable body>";
  }
}
