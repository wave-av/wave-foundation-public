// provision-subaccount.ts
//
// Creates a Twilio subaccount for a tenant via the Twilio REST API.
//
// Twilio API:
//   POST https://api.twilio.com/2010-04-01/Accounts.json
//   Basic auth: <MASTER_ACCOUNT_SID>:<MASTER_AUTH_TOKEN>
//   Body: FriendlyName=wave-tenant-<tenant_id>

import {
  ProvisionedTwilioSubaccount,
  TenantId,
  TwilioSubaccountError,
} from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const MASTER_SID_REGEX = /^AC[a-f0-9]{32}$/i;
const TWILIO_API_BASE = "https://api.twilio.com/2010-04-01";

export interface ProvisionInput {
  tenant_id: TenantId;
  master_account_sid: string;
  master_auth_token: string;
}

export async function provisionTenantTwilioSubaccount(
  input: ProvisionInput,
  fetchImpl: typeof fetch = fetch,
): Promise<ProvisionedTwilioSubaccount> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new TwilioSubaccountError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!MASTER_SID_REGEX.test(input.master_account_sid)) {
    throw new TwilioSubaccountError("invalid master_account_sid (expect AC<32-hex>)", "INVALID_MASTER_SID");
  }
  if (!input.master_auth_token || input.master_auth_token.length < 30) {
    throw new TwilioSubaccountError("invalid master_auth_token", "INVALID_MASTER_TOKEN");
  }

  const friendly_name = `wave-tenant-${input.tenant_id}`;
  const basicAuth = btoa(`${input.master_account_sid}:${input.master_auth_token}`);

  let res: Response;
  try {
    res = await fetchImpl(`${TWILIO_API_BASE}/Accounts.json`, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ FriendlyName: friendly_name }).toString(),
    });
  } catch (err) {
    throw new TwilioSubaccountError("twilio fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    const text = await safeText(res);
    throw new TwilioSubaccountError(
      `twilio ${res.status}: ${text}`,
      res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
    );
  }

  const body = (await res.json()) as {
    sid?: string;
    auth_token?: string;
    friendly_name?: string;
    status?: string;
    date_created?: string;
  };
  if (!body.sid || !body.auth_token) {
    throw new TwilioSubaccountError("twilio returned no sid/token", "INVALID_RESPONSE");
  }

  const status = body.status ?? "active";
  if (status !== "active" && status !== "suspended" && status !== "closed") {
    throw new TwilioSubaccountError(`unexpected status: ${status}`, "INVALID_STATUS");
  }

  return {
    tenant_id: input.tenant_id,
    account_sid: body.sid,
    auth_token: body.auth_token,
    friendly_name: body.friendly_name ?? friendly_name,
    status: status as ProvisionedTwilioSubaccount["status"],
    date_created: body.date_created ?? new Date().toISOString(),
  };
}

async function safeText(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 500);
  } catch {
    return "<unreadable body>";
  }
}
