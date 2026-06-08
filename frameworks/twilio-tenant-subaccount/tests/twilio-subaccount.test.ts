import { describe, expect, it, vi } from "vitest";
import { provisionTenantTwilioSubaccount } from "../provision-subaccount.js";
import { configureTenantWebhooks } from "../configure-webhook.js";

function fetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => body, text: async () => "" } as Response) as any;
}
function fetchFail(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({ ok: false, status, text: async () => "err" } as Response) as any;
}

const validProvision = {
  tenant_id: "acme",
  master_account_sid: "AC" + "a".repeat(32),
  master_auth_token: "a".repeat(40),
} as const;

describe("provisionTenantTwilioSubaccount", () => {
  it("happy path returns account_sid + auth_token", async () => {
    const fetchImpl = fetchOk({
      sid: "AC" + "b".repeat(32),
      auth_token: "tok_xyz",
      friendly_name: "wave-tenant-acme",
      status: "active",
      date_created: "2026-06-04T00:00:00Z",
    });
    const r = await provisionTenantTwilioSubaccount(validProvision, fetchImpl);
    expect(r.account_sid).toBe("AC" + "b".repeat(32));
    expect(r.auth_token).toBe("tok_xyz");
    expect(r.status).toBe("active");
  });

  it("rejects invalid master_account_sid shape", async () => {
    await expect(
      provisionTenantTwilioSubaccount({ ...validProvision, master_account_sid: "not-twilio" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_MASTER_SID" });
  });

  it("rejects short master_auth_token", async () => {
    await expect(
      provisionTenantTwilioSubaccount({ ...validProvision, master_auth_token: "short" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_MASTER_TOKEN" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantTwilioSubaccount(validProvision, fetchFail(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("rejects unknown status value", async () => {
    const fetchImpl = fetchOk({
      sid: "AC" + "b".repeat(32),
      auth_token: "t",
      status: "weird-state",
    });
    await expect(
      provisionTenantTwilioSubaccount(validProvision, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_STATUS" });
  });
});

describe("configureTenantWebhooks", () => {
  const validConfig = {
    tenant_id: "acme",
    subaccount_sid: "AC" + "b".repeat(32),
    subaccount_auth_token: "t".repeat(40),
    voice_url: "https://dispatch.wave.online/v1/phone/webhook/acme",
    sms_url: "https://dispatch.wave.online/v1/phone/webhook/acme",
  } as const;

  it("happy path returns tenant_id + updated_at", async () => {
    const r = await configureTenantWebhooks(validConfig, fetchOk({}));
    expect(r.tenant_id).toBe("acme");
    expect(r.updated_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("rejects non-HTTPS voice_url", async () => {
    await expect(
      configureTenantWebhooks(
        { ...validConfig, voice_url: "http://example.com" },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_URL" });
  });

  it("rejects invalid subaccount_sid shape", async () => {
    await expect(
      configureTenantWebhooks(
        { ...validConfig, subaccount_sid: "not-twilio" },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_SUB_SID" });
  });

  it("forwards fallback URLs when provided", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true, status: 200, json: async () => ({}),
    } as Response) as any;
    await configureTenantWebhooks(
      {
        ...validConfig,
        voice_fallback_url: "https://fallback.wave.online/voice",
        sms_fallback_url: "https://fallback.wave.online/sms",
      },
      fetchImpl,
    );
    const callBody = (fetchImpl as any).mock.calls[0][1].body as string;
    expect(callBody).toContain("VoiceFallbackUrl");
    expect(callBody).toContain("SmsFallbackUrl");
  });
});
