// configure-webhook.ts
//
// Sets the voice/SMS webhook URLs on a tenant's Twilio subaccount so inbound traffic dispatches
// to dispatch.wave.online/v1/phone/webhook/<tenant_id>.

import { TenantId, TwilioSubaccountError } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const SUB_SID_REGEX = /^AC[a-f0-9]{32}$/i;
const TWILIO_API_BASE = "https://api.twilio.com/2010-04-01";

export interface ConfigureWebhookInput {
  tenant_id: TenantId;
  subaccount_sid: string;
  subaccount_auth_token: string;
  voice_url: string;
  sms_url: string;
  /** Optional fallback URL Twilio uses if the primary times out. */
  voice_fallback_url?: string;
  sms_fallback_url?: string;
}

export async function configureTenantWebhooks(
  input: ConfigureWebhookInput,
  fetchImpl: typeof fetch = fetch,
): Promise<{ tenant_id: TenantId; updated_at: string }> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new TwilioSubaccountError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!SUB_SID_REGEX.test(input.subaccount_sid)) {
    throw new TwilioSubaccountError("invalid subaccount_sid", "INVALID_SUB_SID");
  }
  if (!isHttpsUrl(input.voice_url) || !isHttpsUrl(input.sms_url)) {
    throw new TwilioSubaccountError("voice_url + sms_url must be https://", "INVALID_URL");
  }
  if (input.voice_fallback_url && !isHttpsUrl(input.voice_fallback_url)) {
    throw new TwilioSubaccountError("voice_fallback_url must be https://", "INVALID_URL");
  }
  if (input.sms_fallback_url && !isHttpsUrl(input.sms_fallback_url)) {
    throw new TwilioSubaccountError("sms_fallback_url must be https://", "INVALID_URL");
  }

  const basicAuth = btoa(`${input.subaccount_sid}:${input.subaccount_auth_token}`);
  const params = new URLSearchParams({
    VoiceUrl: input.voice_url,
    SmsUrl: input.sms_url,
  });
  if (input.voice_fallback_url) params.set("VoiceFallbackUrl", input.voice_fallback_url);
  if (input.sms_fallback_url) params.set("SmsFallbackUrl", input.sms_fallback_url);

  let res: Response;
  try {
    res = await fetchImpl(
      `${TWILIO_API_BASE}/Accounts/${encodeURIComponent(input.subaccount_sid)}.json`,
      {
        method: "POST",
        headers: {
          "Authorization": `Basic ${basicAuth}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: params.toString(),
      },
    );
  } catch (err) {
    throw new TwilioSubaccountError("twilio update fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new TwilioSubaccountError(
      `twilio update ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  return { tenant_id: input.tenant_id, updated_at: new Date().toISOString() };
}

function isHttpsUrl(s: string): boolean {
  try {
    return new URL(s).protocol === "https:";
  } catch {
    return false;
  }
}
