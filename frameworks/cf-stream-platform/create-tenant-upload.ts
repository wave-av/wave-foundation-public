// create-tenant-upload.ts
//
// Creates a tus-resumable upload URL on CF Stream tagged with `wave_tenant_id`.
// The upload URL is single-use and short-lived — handed to the tenant's client.

import { StreamPlatformError, StreamUpload, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const CF_API_BASE = "https://api.cloudflare.com/client/v4";

export interface UploadInput {
  tenant_id: TenantId;
  cf_account_id: string;
  cf_api_token: string;
  /** Max upload size in bytes. CF default = 30GB. */
  max_size_bytes?: number;
  /** Allowed origin for the upload (CORS). */
  allowed_origin?: string;
  /** Optional caller-provided meta (e.g., session_id) — merged after `wave_tenant_id`. */
  meta?: Record<string, string>;
}

export async function createTenantUpload(
  input: UploadInput,
  fetchImpl: typeof fetch = fetch,
): Promise<StreamUpload> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new StreamPlatformError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!/^[a-f0-9]{32}$/i.test(input.cf_account_id)) {
    throw new StreamPlatformError("invalid cf_account_id", "INVALID_ACCOUNT_ID");
  }
  if (input.max_size_bytes !== undefined &&
      (!Number.isInteger(input.max_size_bytes) || input.max_size_bytes < 1024)) {
    throw new StreamPlatformError("invalid max_size_bytes", "INVALID_MAX_SIZE");
  }

  // Tenant-meta MUST win: caller-provided wave_tenant_id is overwritten.
  const meta = {
    ...(input.meta ?? {}),
    wave_tenant_id: input.tenant_id,
  };

  let res: Response;
  try {
    res = await fetchImpl(`${CF_API_BASE}/accounts/${input.cf_account_id}/stream/direct_upload`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${input.cf_api_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        maxDurationSeconds: 14400, // 4h ceiling
        meta,
        allowedOrigins: input.allowed_origin ? [input.allowed_origin] : undefined,
      }),
    });
  } catch (err) {
    throw new StreamPlatformError("cf stream upload create fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new StreamPlatformError(`cf stream upload create ${res.status}`, "API_ERROR");
  }

  const body = (await res.json()) as {
    success: boolean;
    result?: { uid: string; uploadURL: string };
  };
  if (!body.success || !body.result) {
    throw new StreamPlatformError("cf stream upload no result", "INVALID_RESPONSE");
  }

  return {
    uid: body.result.uid,
    upload_url: body.result.uploadURL,
    expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(), // CF default ~30min
  };
}
