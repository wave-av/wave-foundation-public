import { describe, expect, it, vi } from "vitest";
import { provisionTenantKvNamespace } from "../provision-namespace.js";
import { TenantKVClient } from "../tenant-kv-client.js";

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

describe("provisionTenantKvNamespace", () => {
  it("happy path returns namespace_id + binding_name", async () => {
    const fetchImpl = fetchOk({ success: true, result: { id: "ns_abc" } });
    const r = await provisionTenantKvNamespace(validProvision, fetchImpl);
    expect(r.namespace_id).toBe("ns_abc");
    expect(r.binding_name).toBe("TENANT_ACME_KV");
  });

  it("accepts custom binding_name", async () => {
    const fetchImpl = fetchOk({ success: true, result: { id: "ns_x" } });
    const r = await provisionTenantKvNamespace(
      { ...validProvision, binding_name: "TENANT_X_KV" },
      fetchImpl,
    );
    expect(r.binding_name).toBe("TENANT_X_KV");
  });

  it("rejects invalid binding_name", async () => {
    await expect(
      provisionTenantKvNamespace({ ...validProvision, binding_name: "lowercase-bad" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_BINDING" });
  });

  it("maps 409 to NAMESPACE_EXISTS", async () => {
    await expect(
      provisionTenantKvNamespace(validProvision, fetchFail(409)),
    ).rejects.toMatchObject({ code: "NAMESPACE_EXISTS" });
  });
});

function mockKVNamespace() {
  return {
    get: vi.fn().mockResolvedValue("value"),
    put: vi.fn().mockResolvedValue(undefined),
    delete: vi.fn().mockResolvedValue(undefined),
    list: vi.fn().mockResolvedValue({ keys: [{ name: "acme:session:1" }, { name: "acme:other:2" }], list_complete: true }),
  };
}

describe("TenantKVClient", () => {
  it("get prefixes key with tenant_id", async () => {
    const ns = mockKVNamespace();
    const c = new TenantKVClient(ns as any, "acme");
    await c.get("session:1");
    expect(ns.get).toHaveBeenCalledWith("acme:session:1", undefined);
  });

  it("put prefixes key + forwards options", async () => {
    const ns = mockKVNamespace();
    const c = new TenantKVClient(ns as any, "acme");
    await c.put("session:1", "v", { expirationTtl: 3600 });
    expect(ns.put).toHaveBeenCalledWith("acme:session:1", "v", { expirationTtl: 3600 });
  });

  it("rejects short expirationTtl", async () => {
    const ns = mockKVNamespace();
    const c = new TenantKVClient(ns as any, "acme");
    await expect(c.put("k", "v", { expirationTtl: 10 })).rejects.toMatchObject({ code: "INVALID_TTL" });
  });

  it("rejects invalid key chars", async () => {
    const ns = mockKVNamespace();
    const c = new TenantKVClient(ns as any, "acme");
    await expect(c.get("bad key with spaces")).rejects.toMatchObject({ code: "INVALID_KEY" });
  });

  it("list force-prefixes + strips returned keys", async () => {
    const ns = mockKVNamespace();
    const c = new TenantKVClient(ns as any, "acme");
    const r = await c.list({ prefix: "session:" });
    expect(ns.list).toHaveBeenCalledWith({ prefix: "acme:session:", limit: undefined, cursor: undefined });
    expect(r.keys[0].name).toBe("session:1"); // tenant prefix stripped
  });

  it("rejects invalid tenant_id at construction", () => {
    const ns = mockKVNamespace();
    expect(() => new TenantKVClient(ns as any, "../etc")).toThrow(/INVALID_TENANT_ID/);
  });
});
