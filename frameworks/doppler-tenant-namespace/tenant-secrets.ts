// tenant-secrets.ts — canonical Doppler tenant-namespace API (ADR-002).
//
// Mirrors the WAVE control plane's secrets.ts; the foundation copy is the
// SSoT. Any divergence is a bug — `consume.sh` vendors this to spokes.

const DOPPLER_API = "https://api.doppler.com/v3";

const TENANT_ID_RE = /^[a-zA-Z0-9_-]{1,64}$/;
const SECRET_NAME_RE = /^[A-Z][A-Z0-9_]{0,63}$/;

interface DopplerConfig {
  /** Tenant-scoped service-account token (rotates per tenant; NEVER a global wave/* token). */
  token: string;
  project: "wave";
  config: "tenants";
}

function tenantPrefix(tenantId: string): string {
  if (!TENANT_ID_RE.test(tenantId)) {
    throw new Error(`doppler-tenant-namespace: invalid tenant_id ${JSON.stringify(tenantId)}`);
  }
  return `${tenantId}/`;
}

/** Fetch all secrets for one tenant, prefix-stripped. */
export async function secretsFor(
  tenantId: string,
  doppler: DopplerConfig,
): Promise<Record<string, string>> {
  const prefix = tenantPrefix(tenantId);
  const url = `${DOPPLER_API}/configs/config/secrets?project=${doppler.project}&config=${doppler.config}`;
  const resp = await fetch(url, {
    headers: { authorization: `Bearer ${doppler.token}` },
  });
  if (!resp.ok) {
    throw new Error(`doppler-tenant-namespace: GET failed ${resp.status}`);
  }
  const data: { secrets: Record<string, { computed: string }> } = await resp.json();
  const out: Record<string, string> = {};
  for (const [name, val] of Object.entries(data.secrets ?? {})) {
    if (!name.startsWith(prefix)) continue;
    out[name.slice(prefix.length)] = val.computed;
  }
  return out;
}

/** Write one secret for one tenant — prefix is prepended automatically. */
export async function setSecret(
  tenantId: string,
  name: string,
  value: string,
  doppler: DopplerConfig,
): Promise<void> {
  if (!SECRET_NAME_RE.test(name)) {
    throw new Error(`doppler-tenant-namespace: invalid name ${JSON.stringify(name)} — must be SCREAMING_SNAKE_CASE`);
  }
  const fullName = `${tenantPrefix(tenantId)}${name}`;
  const url = `${DOPPLER_API}/configs/config/secrets?project=${doppler.project}&config=${doppler.config}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `Bearer ${doppler.token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ secrets: { [fullName]: value } }),
  });
  if (!resp.ok) {
    throw new Error(`doppler-tenant-namespace: POST failed ${resp.status}`);
  }
}
