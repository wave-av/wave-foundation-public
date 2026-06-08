import { describe, expect, it, vi } from "vitest";
import { provisionTenantStream } from "../provision-tenant-stream.js";
import { createTenantUpload } from "../create-tenant-upload.js";

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

describe("provisionTenantStream", () => {
  it("happy path returns signing key", async () => {
    const fetchImpl = fetchOk({ success: true, result: { id: "key_abc", pem: "----PEM----", jwk: {} } });
    const r = await provisionTenantStream(validProvision, fetchImpl);
    expect(r.signing_key_id).toBe("key_abc");
    expect(r.signing_key_pem).toBe("----PEM----");
    expect(r.cf_api_token_id).toMatch(/^a{8}/); // hint only
    expect(r.cf_api_token_id).not.toContain("…aaa"); // never echo full
  });

  it("rejects invalid tenant_id", async () => {
    await expect(
      provisionTenantStream({ ...validProvision, tenant_id: "../etc" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("rejects malformed cf_account_id (not 32 hex)", async () => {
    await expect(
      provisionTenantStream({ ...validProvision, cf_account_id: "short" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_ACCOUNT_ID" });
  });

  it("rejects short api token", async () => {
    await expect(
      provisionTenantStream({ ...validProvision, cf_api_token: "short" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_TOKEN" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantStream(validProvision, fetchFail(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("maps other failure to API_ERROR", async () => {
    await expect(
      provisionTenantStream(validProvision, fetchFail(500)),
    ).rejects.toMatchObject({ code: "API_ERROR" });
  });
});

describe("createTenantUpload", () => {
  const validUpload = {
    tenant_id: "acme",
    cf_account_id: "abcdef0123456789abcdef0123456789",
    cf_api_token: "a".repeat(40),
  } as const;

  it("happy path returns upload URL", async () => {
    const fetchImpl = fetchOk({ success: true, result: { uid: "vid_xyz", uploadURL: "https://upload.example/abc" } });
    const r = await createTenantUpload(validUpload, fetchImpl);
    expect(r.uid).toBe("vid_xyz");
    expect(r.upload_url).toBe("https://upload.example/abc");
  });

  it("overrides caller meta.wave_tenant_id (anti-spoof)", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true, status: 200,
      json: async () => ({ success: true, result: { uid: "u", uploadURL: "https://x" } }),
    } as Response) as any;
    await createTenantUpload(
      { ...validUpload, meta: { wave_tenant_id: "EVIL_ID", session: "x" } },
      fetchImpl,
    );
    const callBody = JSON.parse(fetchImpl.mock.calls[0][1].body);
    expect(callBody.meta.wave_tenant_id).toBe("acme");
    expect(callBody.meta.session).toBe("x");
  });

  it("rejects invalid max_size_bytes", async () => {
    await expect(
      createTenantUpload({ ...validUpload, max_size_bytes: 100 }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_MAX_SIZE" });
  });
});
