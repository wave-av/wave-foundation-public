// send-email.ts
//
// Tenant-scoped send wrapper. Picks the right `from` based on the tenant_id and forwards to Resend.
// Throws if the tenant's domain isn't verified yet.

import { ResendDomainError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const RESEND_API_BASE = "https://api.resend.com";

export interface SendInput {
  tenant_id: TenantId;
  /** Caller resolves this from the tenant record (Supabase/Doppler). */
  sending_domain: string; // e.g. mail.acme.wave.online
  from_local_part: string; // "noreply" -> noreply@mail.acme.wave.online
  to: string | string[];
  subject: string;
  html?: string;
  text?: string;
  reply_to?: string;
  tags?: Array<{ name: string; value: string }>;
}

export interface SendResult {
  message_id: string;
  tenant_id: TenantId;
}

export async function sendEmail(
  resendApiKey: string,
  input: SendInput,
  fetchImpl: typeof fetch = fetch,
): Promise<SendResult> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new ResendDomainError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!input.html && !input.text) {
    throw new ResendDomainError("must supply html or text", "EMPTY_BODY");
  }
  if (!/^[a-z0-9._+-]+$/i.test(input.from_local_part)) {
    throw new ResendDomainError("invalid from_local_part", "INVALID_FROM");
  }

  const from = `${input.from_local_part}@${input.sending_domain}`;

  let res: Response;
  try {
    res = await fetchImpl(`${RESEND_API_BASE}/emails`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: input.to,
        subject: input.subject,
        html: input.html,
        text: input.text,
        reply_to: input.reply_to,
        tags: [
          { name: "wave_tenant_id", value: input.tenant_id },
          ...(input.tags ?? []),
        ],
      }),
    });
  } catch (err) {
    throw new ResendDomainError("resend send fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new ResendDomainError(
      `resend send ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : res.status === 403 ? "DOMAIN_NOT_VERIFIED" : "API_ERROR",
    );
  }

  const body = (await res.json()) as { id?: string };
  if (!body.id) {
    throw new ResendDomainError("resend send returned no message id", "NO_MESSAGE_ID");
  }
  return { message_id: body.id, tenant_id: input.tenant_id };
}
