import { describe, expect, it, vi } from "vitest";
import { provisionTenantHook0App } from "../provision-app.js";
import { emitHook0Event } from "../emit-event.js";

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

const validProvision = {
  tenant_id: "acme",
  base_url: "https://app.hook0.com",
  organization_id: "11111111-1111-4111-8111-111111111111",
  api_token: "t".repeat(40),
};

describe("provisionTenantHook0App", () => {
  it("happy path returns application_id + application_secret", async () => {
    const r = await provisionTenantHook0App(
      validProvision,
      fetchOk({
        application_id: "22222222-2222-4222-8222-222222222222",
        application_secret: "s".repeat(40),
        created_at: "2026-06-04T00:00:00Z",
      }),
    );
    expect(r.application_id).toMatch(/^[0-9a-f-]{36}$/);
    expect(r.application_secret).toHaveLength(40);
  });

  it("rejects non-https base_url", async () => {
    await expect(
      provisionTenantHook0App({ ...validProvision, base_url: "http://insecure" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_BASE_URL" });
  });

  it("rejects non-UUID organization_id", async () => {
    await expect(
      provisionTenantHook0App({ ...validProvision, organization_id: "abc" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_ORG_ID" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantHook0App(validProvision, fetchStatus(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("maps 409 to APP_EXISTS", async () => {
    await expect(
      provisionTenantHook0App(validProvision, fetchStatus(409)),
    ).rejects.toMatchObject({ code: "APP_EXISTS" });
  });
});

describe("emitHook0Event", () => {
  const validEmit = {
    base_url: "https://app.hook0.com",
    application_secret: "s".repeat(40),
    event: {
      event_id: "33333333-3333-4333-8333-333333333333",
      event_type: "wave.session.recording_ready",
      occurred_at: "2026-06-04T00:00:00Z",
      payload: { foo: "bar" },
    },
  };

  it("happy path returns accepted_at", async () => {
    const r = await emitHook0Event(validEmit, fetchOk({}));
    expect(r.event_id).toBe(validEmit.event.event_id);
  });

  it("rejects non-UUID event_id", async () => {
    await expect(
      emitHook0Event(
        { ...validEmit, event: { ...validEmit.event, event_id: "not-uuid" } },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_EVENT_ID" });
  });

  it("rejects bad event_type", async () => {
    await expect(
      emitHook0Event(
        {
          ...validEmit,
          event: { ...validEmit.event, event_type: "BadType With Spaces!" },
        },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_EVENT_TYPE" });
  });

  it("rejects bad timestamp", async () => {
    await expect(
      emitHook0Event(
        { ...validEmit, event: { ...validEmit.event, occurred_at: "tomorrow" } },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "INVALID_TIMESTAMP" });
  });

  it("rejects oversized payload", async () => {
    const huge = "x".repeat(300 * 1024);
    await expect(
      emitHook0Event(
        { ...validEmit, event: { ...validEmit.event, payload: { huge } } },
        fetchOk({}),
      ),
    ).rejects.toMatchObject({ code: "PAYLOAD_TOO_LARGE" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(emitHook0Event(validEmit, fetchStatus(401))).rejects.toMatchObject({
      code: "UNAUTHORIZED",
    });
  });

  it("rejects bad application_secret", async () => {
    await expect(
      emitHook0Event({ ...validEmit, application_secret: "tiny" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_APP_SECRET" });
  });
});
