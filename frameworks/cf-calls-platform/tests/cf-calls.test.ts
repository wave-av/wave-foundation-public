import { describe, expect, it, vi } from "vitest";
import { provisionTenantCallsApp } from "../provision-tenant-app.js";
import { issueTenantTurnCredential } from "../issue-turn-credential.js";

function fetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({ ok: true, status: 200, json: async () => body } as Response) as any;
}
function fetchFail(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({ ok: false, status, text: async () => "err" } as Response) as any;
}

const validProvision = {
  tenant_id: "acme",
  cf_account_id: "abcdef0123456789abcdef0123456789",
  cf_api_token: "a".repeat(40),
} as const;

describe("provisionTenantCallsApp", () => {
  it("happy path returns app id + secret", async () => {
    const fetchImpl = fetchOk({ success: true, result: { uid: "app_abc", secret: "secret_xyz" } });
    const r = await provisionTenantCallsApp(validProvision, fetchImpl);
    expect(r.cf_app_id).toBe("app_abc");
    expect(r.cf_app_secret).toBe("secret_xyz");
    expect(r.tenant_id).toBe("acme");
  });

  it("rejects invalid tenant_id", async () => {
    await expect(
      provisionTenantCallsApp({ ...validProvision, tenant_id: "BAD/PATH" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("rejects invalid account_id", async () => {
    await expect(
      provisionTenantCallsApp({ ...validProvision, cf_account_id: "short" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_ACCOUNT_ID" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantCallsApp(validProvision, fetchFail(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("maps 409 to APP_EXISTS", async () => {
    await expect(
      provisionTenantCallsApp(validProvision, fetchFail(409)),
    ).rejects.toMatchObject({ code: "APP_EXISTS" });
  });

  it("throws INVALID_RESPONSE if secret missing", async () => {
    const fetchImpl = fetchOk({ success: true, result: { uid: "app_abc" } });
    await expect(
      provisionTenantCallsApp(validProvision, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_RESPONSE" });
  });
});

describe("issueTenantTurnCredential", () => {
  const validIssue = {
    tenant_id: "acme",
    cf_app_id: "app_abc123def456",
    cf_app_secret: "secret_xyz789",
    ttl_seconds: 3600,
  } as const;

  it("happy path returns ice servers", async () => {
    const fetchImpl = fetchOk({
      iceServers: [{ urls: "turn:turn.cloudflare.com:3478", username: "u", credential: "c" }],
    });
    const r = await issueTenantTurnCredential(validIssue, fetchImpl);
    expect(r.ice_servers).toHaveLength(1);
    expect(r.ice_servers[0].urls).toContain("turn");
    expect(new Date(r.expires_at).getTime()).toBeGreaterThan(Date.now());
  });

  it("rejects TTL < 60s", async () => {
    await expect(
      issueTenantTurnCredential({ ...validIssue, ttl_seconds: 30 }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_TTL" });
  });

  it("rejects TTL > 86400s", async () => {
    await expect(
      issueTenantTurnCredential({ ...validIssue, ttl_seconds: 200000 }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_TTL" });
  });

  it("rejects short app_id", async () => {
    await expect(
      issueTenantTurnCredential({ ...validIssue, cf_app_id: "x" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_APP_ID" });
  });

  it("throws NO_ICE_SERVERS on empty response", async () => {
    const fetchImpl = fetchOk({ iceServers: [] });
    await expect(
      issueTenantTurnCredential(validIssue, fetchImpl),
    ).rejects.toMatchObject({ code: "NO_ICE_SERVERS" });
  });
});
