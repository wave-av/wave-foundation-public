// provision-number.ts
//
// Purchase a Twilio phone number ON the tenant's subaccount (not the master).
// Two-step: (1) search available numbers, (2) buy by phone_number.
// Webhooks (voice_url/sms_url) are wired in the same purchase call.

import {
  NumberCapability,
  ProvisionedTwilioNumber,
  TenantId,
  TwilioNumberError,
} from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const SUB_SID_REGEX = /^AC[a-f0-9]{32}$/i;
const COUNTRY_REGEX = /^[A-Z]{2}$/;
const AREA_CODE_REGEX = /^\d{3,5}$/;
const E164_REGEX = /^\+\d{8,15}$/;
const TWILIO_API_BASE = "https://api.twilio.com/2010-04-01";
const VALID_CAPABILITIES: ReadonlySet<NumberCapability> = new Set([
  "voice",
  "sms",
  "mms",
  "fax",
]);

export interface ProvisionInput {
  tenant_id: TenantId;
  subaccount_sid: string;
  subaccount_auth_token: string;
  /** ISO 3166-1 alpha-2, e.g. "US". */
  country: string;
  /** Optional area code filter, e.g. "415". */
  area_code?: string;
  /** Required capabilities; AND across the set. */
  required_capabilities: ReadonlyArray<NumberCapability>;
  voice_url?: string;
  sms_url?: string;
  friendly_name?: string;
}

export async function provisionTenantTwilioNumber(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedTwilioNumber> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new TwilioNumberError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!SUB_SID_REGEX.test(input.subaccount_sid)) {
    throw new TwilioNumberError("invalid subaccount_sid", "INVALID_SUB_SID");
  }
  if (!input.subaccount_auth_token || input.subaccount_auth_token.length < 30) {
    throw new TwilioNumberError("invalid subaccount_auth_token", "INVALID_AUTH_TOKEN");
  }
  if (!COUNTRY_REGEX.test(input.country)) {
    throw new TwilioNumberError("country must be ISO-3166-1 alpha-2", "INVALID_COUNTRY");
  }
  if (input.area_code !== undefined && !AREA_CODE_REGEX.test(input.area_code)) {
    throw new TwilioNumberError("invalid area_code", "INVALID_AREA_CODE");
  }
  if (input.required_capabilities.length === 0) {
    throw new TwilioNumberError(
      "required_capabilities must not be empty",
      "INVALID_CAPABILITY",
    );
  }
  for (const c of input.required_capabilities) {
    if (!VALID_CAPABILITIES.has(c)) {
      throw new TwilioNumberError(`unknown capability ${c}`, "INVALID_CAPABILITY");
    }
  }
  if (input.voice_url && !isHttpsUrl(input.voice_url)) {
    throw new TwilioNumberError("voice_url must be https://", "INVALID_URL");
  }
  if (input.sms_url && !isHttpsUrl(input.sms_url)) {
    throw new TwilioNumberError("sms_url must be https://", "INVALID_URL");
  }

  const basicAuth = btoa(`${input.subaccount_sid}:${input.subaccount_auth_token}`);

  // Step 1 — search available numbers
  const searchParams = new URLSearchParams({
    PageSize: "5",
  });
  if (input.area_code) searchParams.set("AreaCode", input.area_code);
  for (const c of input.required_capabilities) {
    // Twilio expects capabilities as boolean filters, e.g. VoiceEnabled=true.
    searchParams.set(capabilityFilterName(c), "true");
  }

  let searchRes: Response;
  try {
    searchRes = await fetchImpl(
      `${TWILIO_API_BASE}/Accounts/${encodeURIComponent(input.subaccount_sid)}/AvailablePhoneNumbers/${encodeURIComponent(input.country)}/Local.json?${searchParams.toString()}`,
      {
        method: "GET",
        headers: { "Authorization": `Basic ${basicAuth}` },
      },
    );
  } catch (err) {
    throw new TwilioNumberError("twilio search fetch failed", "FETCH_FAILED", err);
  }

  if (!searchRes.ok) {
    throw new TwilioNumberError(
      `twilio search ${searchRes.status}`,
      searchRes.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  const searchBody = (await searchRes.json()) as {
    available_phone_numbers?: Array<{ phone_number?: string }>;
  };
  const candidate = searchBody.available_phone_numbers?.find(
    (n) => typeof n.phone_number === "string" && E164_REGEX.test(n.phone_number),
  );
  if (!candidate || !candidate.phone_number) {
    throw new TwilioNumberError("no matching numbers available", "NO_NUMBERS_AVAILABLE");
  }

  // Step 2 — buy that number on the subaccount
  const friendly = input.friendly_name ?? `wave-tenant-${input.tenant_id}`;
  const buyParams = new URLSearchParams({
    PhoneNumber: candidate.phone_number,
    FriendlyName: friendly,
  });
  if (input.voice_url) buyParams.set("VoiceUrl", input.voice_url);
  if (input.sms_url) buyParams.set("SmsUrl", input.sms_url);

  let buyRes: Response;
  try {
    buyRes = await fetchImpl(
      `${TWILIO_API_BASE}/Accounts/${encodeURIComponent(input.subaccount_sid)}/IncomingPhoneNumbers.json`,
      {
        method: "POST",
        headers: {
          "Authorization": `Basic ${basicAuth}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: buyParams.toString(),
      },
    );
  } catch (err) {
    throw new TwilioNumberError("twilio buy fetch failed", "FETCH_FAILED", err);
  }

  if (!buyRes.ok) {
    throw new TwilioNumberError(
      `twilio buy ${buyRes.status}`,
      buyRes.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  const buyBody = (await buyRes.json()) as {
    sid?: string;
    phone_number?: string;
    friendly_name?: string;
    capabilities?: { voice?: boolean; sms?: boolean; mms?: boolean; fax?: boolean };
    voice_url?: string | null;
    sms_url?: string | null;
    date_created?: string;
  };

  if (!buyBody.sid || !buyBody.phone_number || !E164_REGEX.test(buyBody.phone_number)) {
    throw new TwilioNumberError("twilio buy returned malformed body", "INVALID_PHONE_NUMBER");
  }

  return {
    tenant_id: input.tenant_id,
    subaccount_sid: input.subaccount_sid,
    number_sid: buyBody.sid,
    phone_number: buyBody.phone_number,
    friendly_name: buyBody.friendly_name ?? friendly,
    capabilities: {
      voice: buyBody.capabilities?.voice === true,
      sms: buyBody.capabilities?.sms === true,
      mms: buyBody.capabilities?.mms === true,
      fax: buyBody.capabilities?.fax === true,
    },
    voice_url: buyBody.voice_url ?? null,
    sms_url: buyBody.sms_url ?? null,
    date_created: buyBody.date_created ?? new Date().toISOString(),
  };
}

function capabilityFilterName(c: NumberCapability): string {
  switch (c) {
    case "voice":
      return "VoiceEnabled";
    case "sms":
      return "SmsEnabled";
    case "mms":
      return "MmsEnabled";
    case "fax":
      return "FaxEnabled";
  }
}

function isHttpsUrl(s: string): boolean {
  try {
    return new URL(s).protocol === "https:";
  } catch {
    return false;
  }
}
