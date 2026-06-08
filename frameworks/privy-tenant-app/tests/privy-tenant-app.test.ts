import { describe, expect, it, vi } from "vitest";
import { provisionTenantPrivyApp } from "../provision-app.js";
import { TenantPrivyClient } from "../client-wrapper.js";

function fetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => body,
    text: async () => "",
  } as Response) as any;
}
function fetchStatus(status: number, body: any = {}): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  } as Response) as any;
}

const validAppId = "cl" + "a".repeat(20);
const validAppSecret = "s".repeat(40);

describe("provisionTenantPrivyApp", () => {
  it("happy path returns app_id + fingerprint + login_methods", async () => {
    const fetchImpl = fetchOk({ login_methods: ["email", "wallet"] });
    const r = await provisionTenantPrivyApp(
      { tenant_id: "acme", app_id: validAppId, app_secret: validAppSecret },
      fetchImpl,
    );
    expect(r.app_id).toBe(validAppId);
    expect(r.app_secret_fingerprint).toMatch(/^[a-f0-9]{64}$/);
    expect(r.login_methods).toEqual(["email", "wallet"]);
  });

  it("rejects invalid app_id", async () => {
    await expect(
      provisionTenantPrivyApp(
        { tenant_id: "acme", app_id: "short", app_secret: validAppSecret },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_APP_ID" });
  });

  it("rejects short app_secret", async () => {
    await expect(
      provisionTenantPrivyApp(
        { tenant_id: "acme", app_id: validAppId, app_secret: "tiny" },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_APP_SECRET" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantPrivyApp(
        { tenant_id: "acme", app_id: validAppId, app_secret: validAppSecret },
        fetchStatus(401),
      ),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("rejects invalid tenant_id", async () => {
    await expect(
      provisionTenantPrivyApp(
        { tenant_id: "../etc", app_id: validAppId, app_secret: validAppSecret },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });
});

describe("TenantPrivyClient", () => {
  const validUserId = "did:privy:abc123def456";

  it("constructor rejects bad tenant_id", () => {
    expect(() => new TenantPrivyClient("../etc", validAppId, validAppSecret)).toThrow();
  });

  it("constructor rejects bad app_id", () => {
    expect(() => new TenantPrivyClient("acme", "short", validAppSecret)).toThrow();
  });

  it("getUser happy path", async () => {
    const fetchImpl = fetchOk({
      id: validUserId,
      linked_accounts: [{ type: "email", email: "a@b.c" }],
      created_at: 1700000000,
    });
    const c = new TenantPrivyClient("acme", validAppId, validAppSecret, fetchImpl);
    const u = await c.getUser(validUserId);
    expect(u.user_id).toBe(validUserId);
    expect(u.linked_accounts[0].type).toBe("email");
  });

  it("getUser rejects bad user_id", async () => {
    const c = new TenantPrivyClient("acme", validAppId, validAppSecret, fetchOk({}));
    await expect(c.getUser("not-a-did")).rejects.toMatchObject({ code: "INVALID_USER_ID" });
  });

  it("getUser maps 404 to USER_NOT_FOUND", async () => {
    const c = new TenantPrivyClient("acme", validAppId, validAppSecret, fetchStatus(404));
    await expect(c.getUser(validUserId)).rejects.toMatchObject({ code: "USER_NOT_FOUND" });
  });

  it("getUser maps 401 to UNAUTHORIZED", async () => {
    const c = new TenantPrivyClient("acme", validAppId, validAppSecret, fetchStatus(401));
    await expect(c.getUser(validUserId)).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("verifyAccessToken happy path", async () => {
    const fetchImpl = fetchOk({
      user_id: validUserId,
      linked_accounts: [],
      iat: 1700000000,
      exp: 1700003600,
    });
    const c = new TenantPrivyClient("acme", validAppId, validAppSecret, fetchImpl);
    const u = await c.verifyAccessToken("a".repeat(40));
    expect(u.user_id).toBe(validUserId);
    expect(u.expires_at).toBe(1700003600);
  });

  it("verifyAccessToken maps 401 to TOKEN_EXPIRED", async () => {
    const c = new TenantPrivyClient("acme", validAppId, validAppSecret, fetchStatus(401));
    await expect(c.verifyAccessToken("a".repeat(40))).rejects.toMatchObject({
      code: "TOKEN_EXPIRED",
    });
  });

  it("verifyAccessToken rejects short token", async () => {
    const c = new TenantPrivyClient("acme", validAppId, validAppSecret, fetchOk({}));
    await expect(c.verifyAccessToken("x")).rejects.toMatchObject({ code: "INVALID_TOKEN" });
  });

  it("isolation: tenant A client cannot reuse tenant B credentials", async () => {
    // Each client is bound to its own (app_id, app_secret) basic-auth at construction.
    // We assert each client sends its OWN Authorization header.
    const seenAuth: string[] = [];
    const captureFetch = vi.fn().mockImplementation(async (_url: string, init: any) => {
      seenAuth.push(String(init.headers.Authorization));
      return { ok: true, status: 200, json: async () => ({ id: validUserId }) } as Response;
    }) as any;
    const a = new TenantPrivyClient("acme", validAppId, "A".repeat(40), captureFetch);
    const b = new TenantPrivyClient(
      "globex",
      "cl" + "b".repeat(20),
      "B".repeat(40),
      captureFetch,
    );
    await a.getUser(validUserId);
    await b.getUser(validUserId);
    expect(seenAuth[0]).not.toBe(seenAuth[1]);
  });
});
