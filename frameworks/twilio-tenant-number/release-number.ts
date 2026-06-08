// release-number.ts
//
// Release a Twilio number from a tenant's subaccount. Used on tenant churn or number swap.
// Idempotent-ish: 404 is treated as "already released" and returns released_at = null.

import { TenantId, TwilioNumberError } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const SUB_SID_REGEX = /^AC[a-f0-9]{32}$/i;
const NUMBER_SID_REGEX = /^PN[a-f0-9]{32}$/i;
const TWILIO_API_BASE = "https://api.twilio.com/2010-04-01";

export interface ReleaseInput {
  tenant_id: TenantId;
  subaccount_sid: string;
  subaccount_auth_token: string;
  number_sid: string;
}

export async function releaseTenantTwilioNumber(
  input: ReleaseInput,
  fetchImpl: typeof fetch = fetch,
): Promise<{ tenant_id: TenantId; number_sid: string; released_at: string | null }> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new TwilioNumberError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!SUB_SID_REGEX.test(input.subaccount_sid)) {
    throw new TwilioNumberError("invalid subaccount_sid", "INVALID_SUB_SID");
  }
  if (!NUMBER_SID_REGEX.test(input.number_sid)) {
    throw new TwilioNumberError("invalid number_sid", "INVALID_PHONE_NUMBER");
  }
  if (!input.subaccount_auth_token || input.subaccount_auth_token.length < 30) {
    throw new TwilioNumberError("invalid subaccount_auth_token", "INVALID_AUTH_TOKEN");
  }

  const basicAuth = btoa(`${input.subaccount_sid}:${input.subaccount_auth_token}`);

  let res: Response;
  try {
    res = await fetchImpl(
      `${TWILIO_API_BASE}/Accounts/${encodeURIComponent(input.subaccount_sid)}/IncomingPhoneNumbers/${encodeURIComponent(input.number_sid)}.json`,
      {
        method: "DELETE",
        headers: { "Authorization": `Basic ${basicAuth}` },
      },
    );
  } catch (err) {
    throw new TwilioNumberError("twilio release fetch failed", "FETCH_FAILED", err);
  }

  if (res.status === 404) {
    return { tenant_id: input.tenant_id, number_sid: input.number_sid, released_at: null };
  }
  if (!res.ok) {
    throw new TwilioNumberError(
      `twilio release ${res.status}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  return {
    tenant_id: input.tenant_id,
    number_sid: input.number_sid,
    released_at: new Date().toISOString(),
  };
}
