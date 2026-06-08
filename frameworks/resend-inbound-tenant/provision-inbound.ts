// provision-inbound.ts
//
// Create a Resend inbound route for a tenant. The webhook URL is FORCED to
// https://dispatch.wave.online/v1/inbound/<tenant_id> — callers cannot override it,
// which prevents a tenant from being mis-routed to another tenant's worker.

import {
  ProvisionedInboundRoute,
  ResendInboundError,
  TenantId,
} from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const BASE_DOMAIN_REGEX = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;
const RESEND_API_BASE = "https://api.resend.com";

export interface ProvisionInput {
  tenant_id: TenantId;
  api_key: string;
  /** Inbound domain root, e.g. "inbound.wave.online". Tenant address becomes
   * `<tenant_id>@<base_domain>`. */
  base_domain: string;
}

export async function provisionTenantInboundRoute(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedInboundRoute> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new ResendInboundError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!input.api_key || !input.api_key.startsWith("re_") || input.api_key.length < 20) {
    throw new ResendInboundError("invalid Resend api_key", "INVALID_API_KEY");
  }
  const baseDomain = input.base_domain.toLowerCase();
  if (!BASE_DOMAIN_REGEX.test(baseDomain)) {
    throw new ResendInboundError("invalid base_domain", "INVALID_BASE_DOMAIN");
  }

  const inboundAddress = `${input.tenant_id}@${baseDomain}`;
  const webhookUrl = `https://dispatch.wave.online/v1/inbound/${encodeURIComponent(input.tenant_id)}`;

  let res: Response;
  try {
    res = await fetchImpl(`${RESEND_API_BASE}/inbound-routes`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.api_key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name: `wave-tenant-${input.tenant_id}`,
        address: inboundAddress,
        webhook_url: webhookUrl,
      }),
    });
  } catch (err) {
    throw new ResendInboundError("resend inbound fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new ResendInboundError(
      `resend inbound ${res.status}`,
      res.status === 401
        ? "UNAUTHORIZED"
        : res.status === 409
          ? "ROUTE_EXISTS"
          : "API_ERROR",
    );
  }

  const body = (await res.json()) as {
    id?: string;
    webhook_secret?: string;
    created_at?: string;
  };
  if (!body.id || !body.webhook_secret) {
    throw new ResendInboundError("resend returned malformed inbound route", "API_ERROR");
  }

  return {
    tenant_id: input.tenant_id,
    route_id: body.id,
    inbound_address: inboundAddress,
    webhook_url: webhookUrl,
    webhook_secret: body.webhook_secret,
    date_created: body.created_at ?? new Date().toISOString(),
  };
}
