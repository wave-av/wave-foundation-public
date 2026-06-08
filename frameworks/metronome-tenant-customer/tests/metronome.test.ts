import { describe, expect, it, vi } from "vitest";
import { provisionTenantMetronomeCustomer } from "../provision-customer.js";
import { ingestUsageEvents } from "../ingest-events.js";

function fetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => body,
    text: async () => "",
  } as Response) as any;
}
function fetchFail(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: false,
    status,
    text: async () => "err",
    json: async () => ({}),
  } as Response) as any;
}

const validApiKey = "mk_" + "a".repeat(30);
const validCustomerInput = {
  tenant_id: "acme",
  api_key: validApiKey,
};

describe("provisionTenantMetronomeCustomer", () => {
  it("happy path returns customer_id + ingest_alias", async () => {
    const fetchImpl = fetchOk({
      data: { id: "c_abc123", created_at: "2026-06-04T00:00:00Z" },
    });
    const r = await provisionTenantMetronomeCustomer(validCustomerInput, fetchImpl);
    expect(r.customer_id).toBe("c_abc123");
    expect(r.ingest_alias).toBe("wave:acme");
  });

  it("rejects invalid tenant_id", async () => {
    await expect(
      provisionTenantMetronomeCustomer(
        { ...validCustomerInput, tenant_id: "../etc" },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("rejects short api_key", async () => {
    await expect(
      provisionTenantMetronomeCustomer(
        { ...validCustomerInput, api_key: "short" },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_API_KEY" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantMetronomeCustomer(validCustomerInput, fetchFail(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("maps 409 to CUSTOMER_EXISTS", async () => {
    await expect(
      provisionTenantMetronomeCustomer(validCustomerInput, fetchFail(409)),
    ).rejects.toMatchObject({ code: "CUSTOMER_EXISTS" });
  });

  it("rejects response missing customer id", async () => {
    await expect(
      provisionTenantMetronomeCustomer(validCustomerInput, fetchOk({ data: {} })),
    ).rejects.toMatchObject({ code: "API_ERROR" });
  });
});

describe("ingestUsageEvents", () => {
  const validEvent = {
    customer_id: "c_abc123",
    event_type: "wave.video.minutes",
    timestamp: "2026-06-04T00:00:00Z",
    transaction_id: "wave:acme:video:session-1:0",
    properties: { minutes: "12.5" },
  };

  it("happy path returns accepted count", async () => {
    const r = await ingestUsageEvents(validApiKey, [validEvent], fetchOk({}));
    expect(r.accepted).toBe(1);
  });

  it("rejects empty batch", async () => {
    await expect(
      ingestUsageEvents(validApiKey, [], fetchOk({})),
    ).rejects.toMatchObject({ code: "EMPTY_BATCH" });
  });

  it("rejects batches over 100", async () => {
    const big = Array.from({ length: 101 }, (_, i) => ({
      ...validEvent,
      transaction_id: `t-${i}`,
    }));
    await expect(
      ingestUsageEvents(validApiKey, big, fetchOk({})),
    ).rejects.toMatchObject({ code: "BATCH_TOO_LARGE" });
  });

  it("rejects bad event_type", async () => {
    await expect(
      ingestUsageEvents(
        validApiKey,
        [{ ...validEvent, event_type: "BadEventType!" }],
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_EVENT_TYPE" });
  });

  it("rejects bad timestamp", async () => {
    await expect(
      ingestUsageEvents(
        validApiKey,
        [{ ...validEvent, timestamp: "yesterday" }],
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_TIMESTAMP" });
  });

  it("rejects bad transaction_id", async () => {
    await expect(
      ingestUsageEvents(
        validApiKey,
        [{ ...validEvent, transaction_id: "has spaces and $" }],
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_TRANSACTION_ID" });
  });

  it("rejects too many properties", async () => {
    const props: Record<string, string> = {};
    for (let i = 0; i < 51; i++) props[`k${i}`] = "v";
    await expect(
      ingestUsageEvents(
        validApiKey,
        [{ ...validEvent, properties: props }],
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_PROPERTIES" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      ingestUsageEvents(validApiKey, [validEvent], fetchFail(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("rejects short api_key", async () => {
    await expect(
      ingestUsageEvents("k", [validEvent], fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_API_KEY" });
  });
});
