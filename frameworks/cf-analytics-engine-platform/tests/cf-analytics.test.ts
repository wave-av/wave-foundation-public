import { describe, expect, it, vi } from "vitest";
import { writeTenantEvent } from "../write-event.js";
import { queryTenantAnalytics } from "../query-tenant.js";

function mockAEDataset() {
  return { writeDataPoint: vi.fn() };
}

describe("writeTenantEvent", () => {
  it("happy path forwards with tenant_id as index[0]", () => {
    const ds = mockAEDataset();
    writeTenantEvent(ds as any, {
      tenant_id: "acme",
      extra_indexes: ["page_view"],
      blobs: ["/home"],
      doubles: [123],
    });
    expect(ds.writeDataPoint).toHaveBeenCalledWith({
      indexes: ["acme", "page_view"],
      blobs: ["/home"],
      doubles: [123],
    });
  });

  it("rejects invalid tenant_id", () => {
    const ds = mockAEDataset();
    expect(() =>
      writeTenantEvent(ds as any, { tenant_id: "BAD/PATH" }),
    ).toThrow(/INVALID_TENANT_ID/);
    expect(ds.writeDataPoint).not.toHaveBeenCalled();
  });

  it("rejects too many extra_indexes", () => {
    const ds = mockAEDataset();
    expect(() =>
      writeTenantEvent(ds as any, {
        tenant_id: "acme",
        extra_indexes: Array.from({ length: 20 }, (_, i) => `i${i}`),
      }),
    ).toThrow(/TOO_MANY_INDEXES/);
  });

  it("rejects too many blobs", () => {
    const ds = mockAEDataset();
    expect(() =>
      writeTenantEvent(ds as any, {
        tenant_id: "acme",
        blobs: Array.from({ length: 21 }, (_, i) => `${i}`),
      }),
    ).toThrow(/TOO_MANY_BLOBS/);
  });
});

describe("queryTenantAnalytics", () => {
  function mockOkFetch(rows: Record<string, unknown>[]): typeof fetch {
    return vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ data: rows }),
    } as Response) as any;
  }

  const baseInput = {
    account_id: "abc",
    api_token: "xyz",
    tenant_id: "acme",
    dataset: "wave_events",
    select_clause: "blob1 AS path, count() AS hits",
  } as const;

  it("happy path constructs forced tenant WHERE", async () => {
    const fetchImpl = mockOkFetch([{ path: "/", hits: 5 }]);
    const r = await queryTenantAnalytics(baseInput, fetchImpl);
    expect(r.rows).toEqual([{ path: "/", hits: 5 }]);
    expect(r.meta.query).toMatch(/WHERE index1 = 'acme'/);
  });

  it("escapes single-quote in tenant_id", async () => {
    const fetchImpl = mockOkFetch([]);
    // Use a real-shape tenant id (regex allows ; pretend a slip got past)
    // but the regex actually blocks ' so this asserts regex coverage first.
    await expect(
      queryTenantAnalytics({ ...baseInput, tenant_id: "ac'me" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("rejects invalid dataset name", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, dataset: "1bad_name" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_DATASET" });
  });

  it("rejects disallowed select_clause characters", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, select_clause: "blob1; DROP TABLE x;" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_SELECT" });
  });

  it("A5b: rejects forbidden keyword FROM in select_clause", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, select_clause: "blob1 FROM evil" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_SELECT" });
  });

  it("A5b: rejects forbidden keyword UNION in where_extra", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, where_extra: "1=1 UNION SELECT 1" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_WHERE" });
  });

  it("A5b: rejects comment markers --", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, select_clause: "blob1 -- evil" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_SELECT" });
  });

  it("A5b: rejects quote chars in select_clause", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, select_clause: "blob1 = 'x'" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_SELECT" });
  });

  it("A5b: rejects since_iso with quote-escape injection (anchor missing in v1)", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, since_iso: "2026-01-01T'; DROP TABLE x; --" }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_SINCE" });
  });

  it("A5b: accepts strict ISO-8601", async () => {
    const fetchImpl = mockOkFetch([]);
    const r = await queryTenantAnalytics(
      { ...baseInput, since_iso: "2026-06-01T00:00:00Z" },
      fetchImpl,
    );
    expect(r.meta.query).toMatch(/timestamp >= toDateTime\('2026-06-01T00:00:00Z'\)/);
  });

  it("rejects out-of-range limit", async () => {
    const fetchImpl = mockOkFetch([]);
    await expect(
      queryTenantAnalytics({ ...baseInput, limit: 0 }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_LIMIT" });
    await expect(
      queryTenantAnalytics({ ...baseInput, limit: 100000 }, fetchImpl),
    ).rejects.toMatchObject({ code: "INVALID_LIMIT" });
  });

  it("appends group/order/limit/since when provided", async () => {
    const fetchImpl = mockOkFetch([]);
    const r = await queryTenantAnalytics(
      {
        ...baseInput,
        group_by: "blob1",
        order_by: "hits DESC",
        limit: 50,
        since_iso: "2026-06-01T00:00:00Z",
      },
      fetchImpl,
    );
    expect(r.meta.query).toMatch(/GROUP BY blob1/);
    expect(r.meta.query).toMatch(/ORDER BY hits DESC/);
    expect(r.meta.query).toMatch(/LIMIT 50/);
    expect(r.meta.query).toMatch(/timestamp >= toDateTime/);
  });
});
