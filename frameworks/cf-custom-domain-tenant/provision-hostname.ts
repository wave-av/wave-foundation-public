// provision-hostname.ts
//
// Create a CF Custom Hostname (SSL-for-SaaS) binding for a tenant's domain.
// Returns the ownership challenge the tenant must add to DNS. status=pending_validation
// is the expected immediate state — NOT an error.

import {
  CustomDomainError,
  HostnameStatus,
  ProvisionedCustomHostname,
  TenantId,
  ValidationMethod,
} from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
// Conservative hostname regex: labels of [a-z0-9-]+ separated by dots, 4-253 chars.
const HOSTNAME_REGEX = /^(?=.{4,253}$)[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;
const CF_ACCOUNT_ID_REGEX = /^[a-f0-9]{32}$/;
const CF_ZONE_ID_REGEX = /^[a-f0-9]{32}$/;
// Hostnames a tenant must NEVER be allowed to claim (those are WAVE-owned + would
// pre-empt our own apex/sub records).
const RESERVED_SUFFIXES = [
  ".wave.online",
  ".wave.app",
  ".wave.dev",
];
const RESERVED_EXACT = ["wave.online", "wave.app", "wave.dev"];
const VALID_VALIDATION: ReadonlySet<ValidationMethod> = new Set(["http", "txt", "email"]);

export interface ProvisionInput {
  tenant_id: TenantId;
  hostname: string;
  account_id: string;
  zone_id: string;
  api_token: string;
  validation_method?: ValidationMethod;
  /** Optional Worker route binding for this hostname (e.g. "wave-dispatch"). */
  origin_worker?: string;
}

export async function provisionTenantCustomHostname(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedCustomHostname> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new CustomDomainError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  const hostname = input.hostname.toLowerCase();
  if (!HOSTNAME_REGEX.test(hostname)) {
    throw new CustomDomainError("invalid hostname", "INVALID_HOSTNAME");
  }
  if (RESERVED_EXACT.includes(hostname) || RESERVED_SUFFIXES.some((s) => hostname.endsWith(s))) {
    throw new CustomDomainError("hostname reserved for WAVE", "RESERVED_HOSTNAME");
  }
  if (!CF_ACCOUNT_ID_REGEX.test(input.account_id)) {
    throw new CustomDomainError("invalid account_id", "INVALID_ACCOUNT_ID");
  }
  if (!CF_ZONE_ID_REGEX.test(input.zone_id)) {
    throw new CustomDomainError("invalid zone_id", "INVALID_ZONE_ID");
  }
  if (!input.api_token || input.api_token.length < 30) {
    throw new CustomDomainError("invalid api_token", "INVALID_API_TOKEN");
  }
  const method = input.validation_method ?? "txt";
  if (!VALID_VALIDATION.has(method)) {
    throw new CustomDomainError("invalid validation_method", "INVALID_VALIDATION_METHOD");
  }

  let res: Response;
  try {
    res = await fetchImpl(
      `https://api.cloudflare.com/client/v4/zones/${encodeURIComponent(input.zone_id)}/custom_hostnames`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${input.api_token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          hostname,
          ssl: {
            method,
            type: "dv",
            settings: { min_tls_version: "1.2", http2: "on" },
          },
        }),
      },
    );
  } catch (err) {
    throw new CustomDomainError("cf custom-hostname fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new CustomDomainError(
      `cf custom-hostname ${res.status}`,
      res.status === 401
        ? "UNAUTHORIZED"
        : res.status === 409
          ? "HOSTNAME_EXISTS"
          : "API_ERROR",
    );
  }

  const body = (await res.json()) as {
    result?: {
      id?: string;
      hostname?: string;
      status?: HostnameStatus;
      ownership_verification?: { name?: string; value?: string; type?: string };
      created_at?: string;
    };
  };
  const r = body.result;
  if (!r || !r.id || !r.hostname || !r.status) {
    throw new CustomDomainError("cf returned malformed custom-hostname", "API_ERROR");
  }

  const challenge =
    r.ownership_verification && r.ownership_verification.name && r.ownership_verification.value
      ? {
          name: r.ownership_verification.name,
          value: r.ownership_verification.value,
          type: "TXT" as const,
        }
      : null;

  return {
    tenant_id: input.tenant_id,
    hostname: r.hostname,
    cf_hostname_id: r.id,
    status: r.status,
    validation_method: method,
    ownership_challenge: challenge,
    date_created: r.created_at ?? new Date().toISOString(),
  };
}
