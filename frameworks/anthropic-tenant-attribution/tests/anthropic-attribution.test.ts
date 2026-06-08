import { describe, expect, it, vi } from "vitest";
import { TenantAnthropicClient } from "../client-wrapper.js";
import type { AnthropicAttributionEvent } from "../types.js";

function fetchOk(body: any, headers: Record<string, string> = {}): typeof fetch {
  const h = new Headers(headers);
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    headers: h,
    json: async () => body,
  } as Response) as any;
}
function fetchStatus(status: number, headers: Record<string, string> = {}): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    headers: new Headers(headers),
    text: async () => "err",
    json: async () => ({}),
  } as Response) as any;
}

const validKey = "sk-ant-" + "a".repeat(40);
const validParams = {
  model: "claude-sonnet-4-5",
  max_tokens: 256,
  messages: [{ role: "user" as const, content: "hello" }],
};
const happyBody = {
  id: "msg_abc",
  type: "message",
  role: "assistant",
  content: [{ type: "text", text: "hi" }],
  model: "claude-sonnet-4-5",
  stop_reason: "end_turn",
  usage: { input_tokens: 5, output_tokens: 3 },
};

describe("TenantAnthropicClient", () => {
  it("constructor rejects bad tenant_id", () => {
    expect(() => new TenantAnthropicClient("../etc", validKey, () => {})).toThrow();
  });

  it("constructor rejects non-sk- api_key", () => {
    expect(() => new TenantAnthropicClient("acme", "abc12345678901234567890", () => {})).toThrow();
  });

  it("happy path returns response + emits event with usage", async () => {
    const events: AnthropicAttributionEvent[] = [];
    const c = new TenantAnthropicClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      fetchOk(happyBody, { "request-id": "req_xyz" }),
    );
    const r = await c.messages(validParams);
    expect(r.id).toBe("msg_abc");
    expect(events).toHaveLength(1);
    expect(events[0].tenant_id).toBe("acme");
    expect(events[0].usage.input_tokens).toBe(5);
    expect(events[0].error).toBe(false);
    expect(events[0].request_id).toBe("req_xyz");
  });

  it("rejects invalid model regex", async () => {
    const c = new TenantAnthropicClient("acme", validKey, () => {}, fetchOk(happyBody));
    await expect(
      c.messages({ ...validParams, model: "gpt-4" }),
    ).rejects.toMatchObject({ code: "INVALID_MODEL" });
  });

  it("rejects empty messages", async () => {
    const c = new TenantAnthropicClient("acme", validKey, () => {}, fetchOk(happyBody));
    await expect(
      c.messages({ ...validParams, messages: [] as any }),
    ).rejects.toMatchObject({ code: "INVALID_REQUEST" });
  });

  it("rejects non-positive max_tokens", async () => {
    const c = new TenantAnthropicClient("acme", validKey, () => {}, fetchOk(happyBody));
    await expect(
      c.messages({ ...validParams, max_tokens: 0 }),
    ).rejects.toMatchObject({ code: "INVALID_REQUEST" });
  });

  it("maps 401 to UNAUTHORIZED + still emits event with error=true", async () => {
    const events: AnthropicAttributionEvent[] = [];
    const c = new TenantAnthropicClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      fetchStatus(401),
    );
    await expect(c.messages(validParams)).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    expect(events).toHaveLength(1);
    expect(events[0].error).toBe(true);
    expect(events[0].status).toBe(401);
  });

  it("maps 429 to RATE_LIMITED + emits event", async () => {
    const events: AnthropicAttributionEvent[] = [];
    const c = new TenantAnthropicClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      fetchStatus(429),
    );
    await expect(c.messages(validParams)).rejects.toMatchObject({ code: "RATE_LIMITED" });
    expect(events[0].error).toBe(true);
    expect(events[0].status).toBe(429);
  });

  it("sink failure does NOT break inference", async () => {
    const c = new TenantAnthropicClient(
      "acme",
      validKey,
      () => {
        throw new Error("metering broke");
      },
      fetchOk(happyBody),
    );
    const r = await c.messages(validParams);
    expect(r.id).toBe("msg_abc");
  });

  it("fetch-throw still emits failure event then rethrows FETCH_FAILED", async () => {
    const events: AnthropicAttributionEvent[] = [];
    const throwingFetch = vi.fn().mockRejectedValue(new Error("network down")) as any;
    const c = new TenantAnthropicClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      throwingFetch,
    );
    await expect(c.messages(validParams)).rejects.toMatchObject({ code: "FETCH_FAILED" });
    expect(events).toHaveLength(1);
    expect(events[0].error).toBe(true);
    expect(events[0].status).toBe(0);
  });
});
