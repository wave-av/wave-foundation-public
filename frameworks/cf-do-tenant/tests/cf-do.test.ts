import { describe, expect, it, vi } from "vitest";
import { TenantDOClient } from "../tenant-do-client.js";

function mockNamespace() {
  const namesSeen: string[] = [];
  return {
    namesSeen,
    idFromName: vi.fn((name: string) => {
      namesSeen.push(name);
      return { toString: () => `id-of-${name}` };
    }),
    newUniqueId: vi.fn(() => ({ toString: () => "unique-1" })),
    get: vi.fn((id: { toString(): string }) => ({
      fetch: async () => new Response(`ok:${id.toString()}`),
    })),
  };
}

describe("TenantDOClient", () => {
  it("rejects invalid tenant_id at construction", () => {
    const ns = mockNamespace();
    expect(() => new TenantDOClient(ns as any, "../etc")).toThrow(/INVALID_TENANT_ID/);
  });

  it("for() scopes logical_name with tenant_id", () => {
    const ns = mockNamespace();
    const c = new TenantDOClient(ns as any, "acme");
    c.for("session-default");
    expect(ns.namesSeen).toContain("acme:session-default");
  });

  it("two tenants requesting same logical_name get DIFFERENT DO names", () => {
    const ns = mockNamespace();
    new TenantDOClient(ns as any, "acme").for("session-default");
    new TenantDOClient(ns as any, "globex").for("session-default");
    expect(ns.namesSeen).toEqual(["acme:session-default", "globex:session-default"]);
  });

  it("rejects invalid logical_name", () => {
    const ns = mockNamespace();
    const c = new TenantDOClient(ns as any, "acme");
    expect(() => c.for("bad name with spaces")).toThrow(/INVALID_LOGICAL_NAME/);
  });

  it("ephemeral() uses newUniqueId", () => {
    const ns = mockNamespace();
    const c = new TenantDOClient(ns as any, "acme");
    c.ephemeral();
    expect(ns.newUniqueId).toHaveBeenCalled();
  });
});
