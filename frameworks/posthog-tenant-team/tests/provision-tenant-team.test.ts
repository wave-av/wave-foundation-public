import { describe, expect, it, vi } from "vitest";
import { provisionTenantPosthogTeam } from "../provision-tenant-team.js";
import { resolveTenantPosthogToken } from "../client-wrapper.js";

function makeFetchImpl(...responses: Array<{ ok: boolean; status?: number; body?: any }>): typeof fetch {
  let i = 0;
  return vi.fn(async () => {
    const r = responses[i++];
    return {
      ok: r.ok,
      status: r.status ?? (r.ok ? 200 : 500),
      json: async () => r.body,
      text: async () => JSON.stringify(r.body),
    } as Response;
  }) as any;
}

const validInput = {
  tenant_id: "acme",
  org_id: "01234567-89ab-cdef-0123-456789abcdef",
} as const;

const validKey = "phc_abcdefghijklmnopqrstuvwxyz0123";

describe("provisionTenantPosthogTeam", () => {
  it("happy path returns ProvisionedPosthogTeam", async () => {
    const fetchImpl = makeFetchImpl({
      ok: true,
      body: { id: 99, name: "Tenant: acme", api_token: "phc_acme_pub_xyz" },
    });
    const r = await provisionTenantPosthogTeam(validKey, validInput, fetchImpl);
    expect(r.posthog_team_id).toBe(99);
    expect(r.posthog_api_token).toBe("phc_acme_pub_xyz");
    expect(r.tenant_id).toBe("acme");
  });

  it("rejects invalid tenant_id", async () => {
    const fetchImpl = makeFetchImpl({ ok: true });
    await expect(
      provisionTenantPosthogTeam(validKey, { ...validInput, tenant_id: "BAD/PATH" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("rejects non-UUID org_id", async () => {
    const fetchImpl = makeFetchImpl({ ok: true });
    await expect(
      provisionTenantPosthogTeam(validKey, { ...validInput, org_id: "not-uuid" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_ORG_ID" });
  });

  it("rejects short api key", async () => {
    const fetchImpl = makeFetchImpl({ ok: true });
    await expect(
      provisionTenantPosthogTeam("short", validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_API_KEY" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    const fetchImpl = makeFetchImpl({ ok: false, status: 401, body: { detail: "bad token" } });
    await expect(
      provisionTenantPosthogTeam(validKey, validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("maps 403 to FORBIDDEN", async () => {
    const fetchImpl = makeFetchImpl({ ok: false, status: 403, body: { detail: "no perm" } });
    await expect(
      provisionTenantPosthogTeam(validKey, validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "FORBIDDEN" });
  });

  it("throws INVALID_RESPONSE if api_token missing", async () => {
    const fetchImpl = makeFetchImpl({ ok: true, body: { id: 1 } });
    await expect(
      provisionTenantPosthogTeam(validKey, validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_RESPONSE" });
  });

  it("rejects http (non-https) host", async () => {
    const fetchImpl = makeFetchImpl({ ok: true });
    await expect(
      provisionTenantPosthogTeam(validKey, { ...validInput, posthog_host: "http://app.posthog.com" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_HOST" });
  });
});

describe("resolveTenantPosthogToken", () => {
  it("returns resolver result", async () => {
    const t = await resolveTenantPosthogToken("acme", { resolver: async () => "phc_x" });
    expect(t).toBe("phc_x");
  });

  it("falls back when null", async () => {
    const t = await resolveTenantPosthogToken("acme", {
      resolver: async () => null,
      fallback_api_token: "phc_fallback",
    });
    expect(t).toBe("phc_fallback");
  });

  it("throws when no result + no fallback", async () => {
    await expect(
      resolveTenantPosthogToken("acme", { resolver: async () => null }),
    ).rejects.toMatchObject({ code: "NO_TOKEN_RESOLVED" });
  });
});
