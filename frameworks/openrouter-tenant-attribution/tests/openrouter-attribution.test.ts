import { describe, expect, it, vi } from "vitest";
import { TenantOpenRouterClient } from "../client-wrapper.js";
import type { OpenRouterAttributionEvent } from "../types.js";

function fetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    headers: new Headers(),
    json: async () => body,
  } as Response) as any;
}
function fetchStatus(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    headers: new Headers(),
    text: async () => "err",
    json: async () => ({}),
  } as Response) as any;
}

const validKey = "sk-or-" + "a".repeat(40);
const validParams = {
  model: "anthropic/claude-sonnet-4-5",
  messages: [{ role: "user" as const, content: "hi" }],
};
const happyBody = {
  id: "gen-abc",
  model: "anthropic/claude-sonnet-4-5",
  choices: [
    {
      index: 0,
      message: { role: "assistant", content: "hi back" },
      finish_reason: "stop",
    },
  ],
  usage: { prompt_tokens: 4, completion_tokens: 2, total_tokens: 6, cost: 0.000042 },
};

describe("TenantOpenRouterClient", () => {
  it("constructor rejects bad tenant_id", () => {
    expect(() => new TenantOpenRouterClient("../etc", validKey, () => {})).toThrow();
  });

  it("constructor rejects non-sk-or- api_key", () => {
    expect(
      () => new TenantOpenRouterClient("acme", "sk-anthropic-" + "x".repeat(40), () => {}),
    ).toThrow();
  });

  it("happy path returns response + event with cost_usd", async () => {
    const events: OpenRouterAttributionEvent[] = [];
    const c = new TenantOpenRouterClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      fetchOk(happyBody),
    );
    const r = await c.chat(validParams);
    expect(r.id).toBe("gen-abc");
    expect(events).toHaveLength(1);
    expect(events[0].usage.cost_usd).toBeCloseTo(0.000042);
    expect(events[0].error).toBe(false);
    expect(events[0].response_id).toBe("gen-abc");
  });

  it("rejects invalid model slug (no slash)", async () => {
    const c = new TenantOpenRouterClient("acme", validKey, () => {}, fetchOk(happyBody));
    await expect(c.chat({ ...validParams, model: "claude-sonnet" })).rejects.toMatchObject({
      code: "INVALID_MODEL",
    });
  });

  it("rejects empty messages", async () => {
    const c = new TenantOpenRouterClient("acme", validKey, () => {}, fetchOk(happyBody));
    await expect(c.chat({ ...validParams, messages: [] as any })).rejects.toMatchObject({
      code: "INVALID_REQUEST",
    });
  });

  it("maps 401 to UNAUTHORIZED + emits failure event", async () => {
    const events: OpenRouterAttributionEvent[] = [];
    const c = new TenantOpenRouterClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      fetchStatus(401),
    );
    await expect(c.chat(validParams)).rejects.toMatchObject({ code: "UNAUTHORIZED" });
    expect(events[0].error).toBe(true);
    expect(events[0].status).toBe(401);
  });

  it("maps 429 to RATE_LIMITED + emits failure event", async () => {
    const events: OpenRouterAttributionEvent[] = [];
    const c = new TenantOpenRouterClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      fetchStatus(429),
    );
    await expect(c.chat(validParams)).rejects.toMatchObject({ code: "RATE_LIMITED" });
    expect(events[0].error).toBe(true);
  });

  it("sink failure does NOT break inference", async () => {
    const c = new TenantOpenRouterClient(
      "acme",
      validKey,
      () => {
        throw new Error("metering broke");
      },
      fetchOk(happyBody),
    );
    const r = await c.chat(validParams);
    expect(r.id).toBe("gen-abc");
  });

  it("fetch-throw still emits event before rethrowing", async () => {
    const events: OpenRouterAttributionEvent[] = [];
    const throwing = vi.fn().mockRejectedValue(new Error("net")) as any;
    const c = new TenantOpenRouterClient(
      "acme",
      validKey,
      (ev) => events.push(ev),
      throwing,
    );
    await expect(c.chat(validParams)).rejects.toMatchObject({ code: "FETCH_FAILED" });
    expect(events).toHaveLength(1);
    expect(events[0].error).toBe(true);
    expect(events[0].status).toBe(0);
  });

  it("sends HTTP-Referer + X-Title + X-Transaction-Id headers", async () => {
    const seen: any[] = [];
    const captureFetch = vi.fn().mockImplementation(async (_url: string, init: any) => {
      seen.push(init.headers);
      return {
        ok: true,
        status: 200,
        headers: new Headers(),
        json: async () => happyBody,
      } as Response;
    }) as any;
    const c = new TenantOpenRouterClient("acme", validKey, () => {}, captureFetch);
    await c.chat({ ...validParams, transaction_id: "txn-1" });
    expect(seen[0]["HTTP-Referer"]).toBe("https://wave.online");
    expect(seen[0]["X-Title"]).toBe("WAVE");
    expect(seen[0]["X-Transaction-Id"]).toBe("txn-1");
  });
});
