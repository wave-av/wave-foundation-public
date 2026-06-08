import { describe, expect, it, vi } from "vitest";
import { provisionTenantSentryProject } from "../provision-tenant-project.js";
import { resolveTenantDsn } from "../client-wrapper.js";

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
  org_slug: "wave-online-llc",
  team_slug: "platform",
} as const;

const validToken = "abcdefghijklmnopqrstuvwxyz123456";

describe("provisionTenantSentryProject", () => {
  it("happy path returns ProvisionedSentryProject with DSN", async () => {
    const fetchImpl = makeFetchImpl(
      { ok: true, body: { id: 42, slug: "tenant-acme" } },
      { ok: true, body: [{ id: 7, dsn: { public: "https://abc@oXX.ingest.sentry.io/42" } }] },
    );
    const result = await provisionTenantSentryProject(validToken, validInput, fetchImpl);

    expect(result.tenant_id).toBe("acme");
    expect(result.sentry_project_slug).toBe("tenant-acme");
    expect(result.sentry_project_id).toBe(42);
    expect(result.dsn_public).toBe("https://abc@oXX.ingest.sentry.io/42");
    expect(result.dsn_id).toBe(7);
  });

  it("rejects invalid tenant_id", async () => {
    const fetchImpl = makeFetchImpl({ ok: true, body: {} });
    await expect(
      provisionTenantSentryProject(validToken, { ...validInput, tenant_id: "../etc" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("rejects invalid org_slug", async () => {
    const fetchImpl = makeFetchImpl({ ok: true, body: {} });
    await expect(
      provisionTenantSentryProject(validToken, { ...validInput, org_slug: "BAD_SLUG" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_SLUG" });
  });

  it("rejects empty/short auth token", async () => {
    const fetchImpl = makeFetchImpl({ ok: true, body: {} });
    await expect(
      provisionTenantSentryProject("short", validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_TOKEN" });
  });

  it("maps 409 to PROJECT_EXISTS", async () => {
    const fetchImpl = makeFetchImpl({ ok: false, status: 409, body: { detail: "exists" } });
    await expect(
      provisionTenantSentryProject(validToken, validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "PROJECT_EXISTS" });
  });

  it("maps other failure to PROJECT_CREATE_FAILED", async () => {
    const fetchImpl = makeFetchImpl({ ok: false, status: 500, body: { detail: "boom" } });
    await expect(
      provisionTenantSentryProject(validToken, validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "PROJECT_CREATE_FAILED" });
  });

  it("throws NO_DSN if keys endpoint returns empty array", async () => {
    const fetchImpl = makeFetchImpl(
      { ok: true, body: { id: 1, slug: "tenant-acme" } },
      { ok: true, body: [] },
    );
    await expect(
      provisionTenantSentryProject(validToken, validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "NO_DSN" });
  });
});

describe("resolveTenantDsn", () => {
  it("returns resolver's DSN when present", async () => {
    const dsn = await resolveTenantDsn("acme", {
      resolver: async () => "https://x@y.ingest.sentry.io/1",
    });
    expect(dsn).toBe("https://x@y.ingest.sentry.io/1");
  });

  it("falls back when resolver returns null", async () => {
    const dsn = await resolveTenantDsn("acme", {
      resolver: async () => null,
      fallback_dsn: "https://fallback@x.ingest.sentry.io/0",
    });
    expect(dsn).toBe("https://fallback@x.ingest.sentry.io/0");
  });

  it("throws when no resolver result and no fallback", async () => {
    await expect(
      resolveTenantDsn("acme", { resolver: async () => null }),
    ).rejects.toMatchObject({ code: "NO_DSN_RESOLVED" });
  });
});
