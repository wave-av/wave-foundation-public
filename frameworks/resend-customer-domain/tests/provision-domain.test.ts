import { describe, expect, it, vi } from "vitest";
import { provisionTenantDomain } from "../provision-domain.js";
import { ResendDomainError } from "../types.js";

function mockFetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => body,
  } as Response) as any;
}

function mockFetchFail(status: number, text = "err"): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: false,
    status,
    text: async () => text,
  } as Response) as any;
}

const validInput = {
  tenant_id: "acme",
  base_domain: "wave.online",
} as const;

describe("provisionTenantDomain", () => {
  it("happy path returns ProvisionedDomain with composed sending_domain", async () => {
    const fetchImpl = mockFetchOk({
      id: "dom_abc123",
      status: "pending",
      records: [
        { type: "MX", name: "mail.acme.wave.online", value: "feedback-smtp.us-east-1.amazonses.com", priority: 10 },
        { type: "TXT", name: "mail.acme.wave.online", value: "v=spf1 include:amazonses.com ~all" },
      ],
    });
    const result = await provisionTenantDomain("re_test_xyz", validInput, fetchImpl);

    expect(result.sending_domain).toBe("mail.acme.wave.online");
    expect(result.resend_domain_id).toBe("dom_abc123");
    expect(result.dns_records).toHaveLength(2);
    expect(result.dns_records[0].type).toBe("MX");
    expect(result.status).toBe("pending");
  });

  it("uses custom subdomain when provided", async () => {
    const fetchImpl = mockFetchOk({ id: "dom_x", status: "pending", records: [] });
    const result = await provisionTenantDomain(
      "re_test_xyz",
      { ...validInput, subdomain: "send" },
      fetchImpl,
    );
    expect(result.sending_domain).toBe("send.acme.wave.online");
  });

  it("rejects invalid tenant_id", async () => {
    const fetchImpl = mockFetchOk({});
    await expect(
      provisionTenantDomain("re_test_xyz", { ...validInput, tenant_id: "../etc" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("rejects invalid base_domain", async () => {
    const fetchImpl = mockFetchOk({});
    await expect(
      provisionTenantDomain("re_test_xyz", { ...validInput, base_domain: "not_a_domain" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_BASE_DOMAIN" });
  });

  it("rejects invalid api key shape", async () => {
    const fetchImpl = mockFetchOk({});
    await expect(
      provisionTenantDomain("not-a-resend-key", validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_API_KEY" });
  });

  it("rejects invalid subdomain", async () => {
    const fetchImpl = mockFetchOk({});
    await expect(
      provisionTenantDomain("re_test_xyz", { ...validInput, subdomain: "BAD..NAME" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_SUBDOMAIN" });
  });

  it("maps 422 to DOMAIN_CONFLICT (already exists)", async () => {
    const fetchImpl = mockFetchFail(422, "domain exists");
    await expect(
      provisionTenantDomain("re_test_xyz", validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "DOMAIN_CONFLICT" });
  });

  it("maps other 4xx/5xx to API_ERROR", async () => {
    const fetchImpl = mockFetchFail(500, "internal");
    await expect(
      provisionTenantDomain("re_test_xyz", validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "API_ERROR" });
  });

  it("wraps network failure in FETCH_FAILED", async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new Error("ECONNREFUSED")) as any;
    await expect(
      provisionTenantDomain("re_test_xyz", validInput, fetchImpl),
    ).rejects.toMatchObject({ code: "FETCH_FAILED" });
  });
});
