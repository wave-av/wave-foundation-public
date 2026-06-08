import { describe, expect, it, vi } from "vitest";
import { provisionTenantD1Database } from "../provision-database.js";
import { TenantD1Client } from "../tenant-d1-client.js";

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

describe("provisionTenantD1Database", () => {
  it("happy path returns database_id + binding_name", async () => {
    const fetchImpl = fetchOk({ success: true, result: { uuid: "uuid-of-acme-db" } });
    const r = await provisionTenantD1Database(validProvision, fetchImpl);
    expect(r.database_id).toBe("uuid-of-acme-db");
    expect(r.database_name).toBe("wave-tenant-acme");
    expect(r.binding_name).toBe("TENANT_ACME_DB");
  });

  it("rejects invalid tenant_id", async () => {
    await expect(
      provisionTenantD1Database({ ...validProvision, tenant_id: "../etc" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("maps 409 to DATABASE_EXISTS", async () => {
    await expect(
      provisionTenantD1Database(validProvision, fetchFail(409)),
    ).rejects.toMatchObject({ code: "DATABASE_EXISTS" });
  });
});

function mockD1() {
  const bindCalls: unknown[][] = [];
  return {
    bindCalls,
    prepare: vi.fn((q: string) => ({
      query: q,
      bind: vi.fn((...vals: unknown[]) => {
        bindCalls.push(vals);
        return { all: async () => ({ results: [], success: true }) };
      }),
    })),
  };
}

describe("TenantD1Client", () => {
  it("auto-prepends tenant_id to bind()", () => {
    const db = mockD1();
    const c = new TenantD1Client(db as any, "acme");
    c.prepare("SELECT * FROM x WHERE tenant_id = ? AND id = ?").bind("u1");
    expect(db.bindCalls[0]).toEqual(["acme", "u1"]);
  });

  it("rejects query without ? placeholders (force bound params)", () => {
    const db = mockD1();
    const c = new TenantD1Client(db as any, "acme");
    expect(() => c.prepare("SELECT * FROM x")).toThrow(/NO_PLACEHOLDERS/);
  });

  it("rejects invalid tenant_id at construction", () => {
    const db = mockD1();
    expect(() => new TenantD1Client(db as any, "../etc")).toThrow(/INVALID_TENANT_ID/);
  });

  it("two tenants bind their own tenant_id even with same query", () => {
    const db1 = mockD1();
    const db2 = mockD1();
    new TenantD1Client(db1 as any, "acme").prepare("WHERE tenant_id = ? AND id = ?").bind("u1");
    new TenantD1Client(db2 as any, "globex").prepare("WHERE tenant_id = ? AND id = ?").bind("u1");
    expect(db1.bindCalls[0]).toEqual(["acme", "u1"]);
    expect(db2.bindCalls[0]).toEqual(["globex", "u1"]);
  });
});
