import { describe, expect, it, vi } from "vitest";
import { provisionTenantCustomHostname } from "../provision-hostname.js";
import { getCustomHostnameStatus } from "../status.js";

function fetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => body,
  } as Response) as any;
}
function fetchStatus(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: async () => "err",
    json: async () => ({}),
  } as Response) as any;
}

const validInput = {
  tenant_id: "acme",
  hostname: "app.acme.com",
  account_id: "a".repeat(32),
  zone_id: "b".repeat(32),
  api_token: "t".repeat(40),
};

const happyBody = {
  result: {
    id: "c".repeat(32),
    hostname: "app.acme.com",
    status: "pending_validation",
    ownership_verification: {
      name: "_acme-challenge.app.acme.com",
      value: "verify-value",
      type: "TXT",
    },
    created_at: "2026-06-04T00:00:00Z",
  },
};

describe("provisionTenantCustomHostname", () => {
  it("happy path returns pending_validation + challenge", async () => {
    const r = await provisionTenantCustomHostname(validInput, fetchOk(happyBody));
    expect(r.status).toBe("pending_validation");
    expect(r.ownership_challenge?.value).toBe("verify-value");
    expect(r.cf_hostname_id).toMatch(/^[a-f0-9]{32}$/);
  });

  it("rejects WAVE-owned suffix", async () => {
    await expect(
      provisionTenantCustomHostname(
        { ...validInput, hostname: "acme.wave.online" },
        fetchOk(happyBody),
      ),
    ).rejects.toMatchObject({ code: "RESERVED_HOSTNAME" });
  });

  it("rejects WAVE apex exact", async () => {
    await expect(
      provisionTenantCustomHostname(
        { ...validInput, hostname: "wave.online" },
        fetchOk(happyBody),
      ),
    ).rejects.toMatchObject({ code: "RESERVED_HOSTNAME" });
  });

  it("rejects invalid hostname shape", async () => {
    await expect(
      provisionTenantCustomHostname(
        { ...validInput, hostname: "not-a-hostname" },
        fetchOk(happyBody),
      ),
    ).rejects.toMatchObject({ code: "INVALID_HOSTNAME" });
  });

  it("rejects bad zone_id", async () => {
    await expect(
      provisionTenantCustomHostname(
        { ...validInput, zone_id: "short" },
        fetchOk(happyBody),
      ),
    ).rejects.toMatchObject({ code: "INVALID_ZONE_ID" });
  });

  it("rejects unknown validation_method", async () => {
    await expect(
      provisionTenantCustomHostname(
        { ...validInput, validation_method: "carrier-pigeon" as any },
        fetchOk(happyBody),
      ),
    ).rejects.toMatchObject({ code: "INVALID_VALIDATION_METHOD" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantCustomHostname(validInput, fetchStatus(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("maps 409 to HOSTNAME_EXISTS", async () => {
    await expect(
      provisionTenantCustomHostname(validInput, fetchStatus(409)),
    ).rejects.toMatchObject({ code: "HOSTNAME_EXISTS" });
  });

  it("rejects malformed CF response", async () => {
    await expect(
      provisionTenantCustomHostname(validInput, fetchOk({ result: {} })),
    ).rejects.toMatchObject({ code: "API_ERROR" });
  });
});

describe("getCustomHostnameStatus", () => {
  const statusInput = {
    tenant_id: "acme",
    zone_id: "b".repeat(32),
    cf_hostname_id: "c".repeat(32),
    api_token: "t".repeat(40),
  };

  it("returns active status", async () => {
    const r = await getCustomHostnameStatus(
      statusInput,
      fetchOk({ result: { hostname: "app.acme.com", status: "active" } }),
    );
    expect(r.status).toBe("active");
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      getCustomHostnameStatus(statusInput, fetchStatus(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });
});
