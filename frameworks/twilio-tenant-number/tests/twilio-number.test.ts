import { describe, expect, it, vi } from "vitest";
import { provisionTenantTwilioNumber } from "../provision-number.js";
import { releaseTenantTwilioNumber } from "../release-number.js";

function searchThenBuy(searchBody: any, buyBody: any): typeof fetch {
  let call = 0;
  return vi.fn().mockImplementation(async () => {
    call += 1;
    if (call === 1) {
      return { ok: true, status: 200, json: async () => searchBody } as Response;
    }
    return { ok: true, status: 200, json: async () => buyBody } as Response;
  }) as any;
}

function fetchFail(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: false,
    status,
    text: async () => "err",
    json: async () => ({}),
  } as Response) as any;
}

const validInput = {
  tenant_id: "acme",
  subaccount_sid: "AC" + "b".repeat(32),
  subaccount_auth_token: "t".repeat(40),
  country: "US",
  area_code: "415",
  required_capabilities: ["voice", "sms"] as const,
  voice_url: "https://dispatch.wave.online/v1/phone/webhook/acme",
  sms_url: "https://dispatch.wave.online/v1/phone/webhook/acme",
};

const happySearch = {
  available_phone_numbers: [{ phone_number: "+14155552671" }],
};
const happyBuy = {
  sid: "PN" + "c".repeat(32),
  phone_number: "+14155552671",
  friendly_name: "wave-tenant-acme",
  capabilities: { voice: true, sms: true, mms: false, fax: false },
  voice_url: validInput.voice_url,
  sms_url: validInput.sms_url,
  date_created: "2026-06-04T00:00:00Z",
};

describe("provisionTenantTwilioNumber", () => {
  it("happy path: search returns one, buy returns PN sid", async () => {
    const fetchImpl = searchThenBuy(happySearch, happyBuy);
    const r = await provisionTenantTwilioNumber(validInput, fetchImpl);
    expect(r.number_sid).toMatch(/^PN[a-f0-9]{32}$/);
    expect(r.phone_number).toBe("+14155552671");
    expect(r.capabilities.voice).toBe(true);
    expect(r.capabilities.sms).toBe(true);
    expect(r.subaccount_sid).toBe(validInput.subaccount_sid);
  });

  it("rejects non-https voice_url", async () => {
    await expect(
      provisionTenantTwilioNumber(
        { ...validInput, voice_url: "http://insecure.example/wh" },
        searchThenBuy(happySearch, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "INVALID_URL" });
  });

  it("rejects invalid subaccount_sid", async () => {
    await expect(
      provisionTenantTwilioNumber(
        { ...validInput, subaccount_sid: "not-twilio" },
        searchThenBuy(happySearch, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "INVALID_SUB_SID" });
  });

  it("rejects empty required_capabilities", async () => {
    await expect(
      provisionTenantTwilioNumber(
        { ...validInput, required_capabilities: [] as any },
        searchThenBuy(happySearch, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "INVALID_CAPABILITY" });
  });

  it("rejects unknown capability", async () => {
    await expect(
      provisionTenantTwilioNumber(
        { ...validInput, required_capabilities: ["telepathy"] as any },
        searchThenBuy(happySearch, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "INVALID_CAPABILITY" });
  });

  it("rejects non-ISO country", async () => {
    await expect(
      provisionTenantTwilioNumber(
        { ...validInput, country: "USA" },
        searchThenBuy(happySearch, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "INVALID_COUNTRY" });
  });

  it("rejects invalid area_code shape", async () => {
    await expect(
      provisionTenantTwilioNumber(
        { ...validInput, area_code: "abc" },
        searchThenBuy(happySearch, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "INVALID_AREA_CODE" });
  });

  it("maps 401 on search to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantTwilioNumber(validInput, fetchFail(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("returns NO_NUMBERS_AVAILABLE when search empty", async () => {
    await expect(
      provisionTenantTwilioNumber(
        validInput,
        searchThenBuy({ available_phone_numbers: [] }, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "NO_NUMBERS_AVAILABLE" });
  });

  it("returns NO_NUMBERS_AVAILABLE when search returns invalid E.164", async () => {
    await expect(
      provisionTenantTwilioNumber(
        validInput,
        searchThenBuy({ available_phone_numbers: [{ phone_number: "garbage" }] }, happyBuy),
      ),
    ).rejects.toMatchObject({ code: "NO_NUMBERS_AVAILABLE" });
  });

  it("rejects malformed buy response (no sid)", async () => {
    await expect(
      provisionTenantTwilioNumber(
        validInput,
        searchThenBuy(happySearch, { phone_number: "+14155552671" }),
      ),
    ).rejects.toMatchObject({ code: "INVALID_PHONE_NUMBER" });
  });
});

describe("releaseTenantTwilioNumber", () => {
  const validRelease = {
    tenant_id: "acme",
    subaccount_sid: "AC" + "b".repeat(32),
    subaccount_auth_token: "t".repeat(40),
    number_sid: "PN" + "c".repeat(32),
  };

  it("happy path returns released_at", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 204,
      text: async () => "",
    } as Response) as any;
    const r = await releaseTenantTwilioNumber(validRelease, fetchImpl);
    expect(r.released_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("404 is treated as already released", async () => {
    const r = await releaseTenantTwilioNumber(validRelease, fetchFail(404));
    expect(r.released_at).toBeNull();
  });

  it("rejects invalid number_sid", async () => {
    await expect(
      releaseTenantTwilioNumber(
        { ...validRelease, number_sid: "not-a-pn-sid" },
        fetchFail(204),
      ),
    ).rejects.toMatchObject({ code: "INVALID_PHONE_NUMBER" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      releaseTenantTwilioNumber(validRelease, fetchFail(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });
});
