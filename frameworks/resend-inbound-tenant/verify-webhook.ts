// verify-webhook.ts
//
// Verify a Svix-style inbound webhook signature from Resend. This is the tenant-isolation
// guarantee: without this, anyone POSTing JSON to /v1/inbound/<tenant_id> could forge
// inbound email for that tenant.
//
// Svix signs `<msg_id>.<timestamp>.<raw_body>` with HMAC-SHA256, base64 encoded, and sends
// the result in `svix-signature` as `v1,<sig>` (potentially multiple comma-separated).

import { InboundEmail, ResendInboundError, TenantId } from "./types.js";

const TIMESTAMP_TOLERANCE_SECONDS = 5 * 60;

export interface VerifyInput {
  tenant_id: TenantId;
  webhook_secret: string;
  /** Raw request body bytes/string — MUST be the exact bytes received, not re-serialized JSON. */
  raw_body: string;
  /** Header values. Lowercased header names match Resend/Svix conventions. */
  svix_id: string;
  svix_timestamp: string;
  svix_signature: string;
}

export async function verifyInboundWebhook(
  input: VerifyInput,
  now: () => number = Date.now,
): Promise<InboundEmail> {
  if (!input.svix_id) {
    throw new ResendInboundError("missing svix-id header", "MISSING_ID_HEADER");
  }
  if (!input.svix_timestamp) {
    throw new ResendInboundError("missing svix-timestamp header", "MISSING_TIMESTAMP_HEADER");
  }
  if (!input.svix_signature) {
    throw new ResendInboundError("missing svix-signature header", "MISSING_SIGNATURE_HEADER");
  }

  const tsSec = Number(input.svix_timestamp);
  if (!Number.isFinite(tsSec)) {
    throw new ResendInboundError("invalid timestamp", "TIMESTAMP_OUT_OF_TOLERANCE");
  }
  const nowSec = Math.floor(now() / 1000);
  if (Math.abs(nowSec - tsSec) > TIMESTAMP_TOLERANCE_SECONDS) {
    throw new ResendInboundError("timestamp out of tolerance", "TIMESTAMP_OUT_OF_TOLERANCE");
  }

  // Svix secrets are typically prefixed `whsec_<base64>` — strip the prefix before decoding.
  const rawSecret = input.webhook_secret.startsWith("whsec_")
    ? input.webhook_secret.slice("whsec_".length)
    : input.webhook_secret;
  const keyBytes = base64ToBytes(rawSecret);
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = `${input.svix_id}.${input.svix_timestamp}.${input.raw_body}`;
  const sigBytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signed));
  const expected = bytesToBase64(new Uint8Array(sigBytes));

  // svix-signature may be `v1,<sig> v1,<sig2>` — accept any version-1 match.
  const candidates = input.svix_signature
    .split(/\s+/)
    .map((s) => s.trim())
    .filter((s) => s.startsWith("v1,"))
    .map((s) => s.slice("v1,".length));
  const ok = candidates.some((c) => timingSafeEqual(c, expected));
  if (!ok) {
    throw new ResendInboundError("signature mismatch", "INVALID_SIGNATURE");
  }

  let payload: any;
  try {
    payload = JSON.parse(input.raw_body);
  } catch (err) {
    throw new ResendInboundError("body not JSON", "API_ERROR", err);
  }

  return {
    tenant_id: input.tenant_id,
    from: String(payload?.from ?? ""),
    to: Array.isArray(payload?.to) ? payload.to.map(String) : [],
    subject: String(payload?.subject ?? ""),
    text: String(payload?.text ?? ""),
    html: typeof payload?.html === "string" ? payload.html : null,
    received_at: typeof payload?.received_at === "string"
      ? payload.received_at
      : new Date().toISOString(),
    message_id: String(payload?.message_id ?? input.svix_id),
  };
}

function base64ToBytes(b64: string): Uint8Array {
  // Add padding if missing (Svix secrets sometimes ship without padding).
  const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
  const bin = atob(b64 + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
