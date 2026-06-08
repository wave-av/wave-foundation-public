// provision-app.ts
//
// Privy apps must be created in the Privy dashboard. This function is a *readiness check*:
// given (tenant_id, app_id, app_secret), it verifies the app is reachable + returns its
// login_methods so callers can persist them + detect drift.
//
// Fingerprint (SHA-256) of app_secret is returned so audit logs can track which secret
// was used WITHOUT ever logging the secret itself.

import { PrivyError, ProvisionedPrivyApp, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
// Privy app_id format: e.g. clxxxxxxxxxxxxxxxxxxx (≥20 alphanumeric chars). Conservative regex.
const APP_ID_REGEX = /^[a-zA-Z0-9]{20,64}$/;
const PRIVY_API_BASE = "https://auth.privy.io/api/v1";

export interface ProvisionInput {
  tenant_id: TenantId;
  app_id: string;
  app_secret: string;
}

export async function provisionTenantPrivyApp(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedPrivyApp> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new PrivyError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!APP_ID_REGEX.test(input.app_id)) {
    throw new PrivyError("invalid app_id", "INVALID_APP_ID");
  }
  if (!input.app_secret || input.app_secret.length < 30) {
    throw new PrivyError("invalid app_secret", "INVALID_APP_SECRET");
  }

  const basicAuth = btoa(`${input.app_id}:${input.app_secret}`);
  let res: Response;
  try {
    res = await fetchImpl(`${PRIVY_API_BASE}/apps/${encodeURIComponent(input.app_id)}`, {
      method: "GET",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "privy-app-id": input.app_id,
      },
    });
  } catch (err) {
    throw new PrivyError("privy fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new PrivyError(
      `privy app readiness ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  const body = (await res.json()) as { login_methods?: string[] };
  const fp = await sha256Hex(input.app_secret);

  return {
    tenant_id: input.tenant_id,
    app_id: input.app_id,
    app_secret_fingerprint: fp,
    login_methods: body.login_methods ?? [],
    verified_at: new Date().toISOString(),
  };
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
