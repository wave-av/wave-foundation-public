import { describe, expect, it, vi } from "vitest";
import { TenantAIClient } from "../tenant-ai-client.js";

function mockAi(result: any = { response: "ok" }) {
  return {
    run: vi.fn(async () => result),
  };
}

describe("TenantAIClient", () => {
  it("rejects invalid tenant_id at construction", () => {
    const ai = mockAi();
    expect(() => new TenantAIClient(ai as any, "../etc")).toThrow(/INVALID_TENANT_ID/);
  });

  it("rejects invalid model identifier", async () => {
    const ai = mockAi();
    const c = new TenantAIClient(ai as any, "acme");
    await expect(c.run("not a model", {})).rejects.toMatchObject({ code: "INVALID_MODEL" });
  });

  it("happy path forwards to ai.run + calls onMeter with tenant_id + ms_latency", async () => {
    const ai = mockAi({ response: "hi" });
    const meter = vi.fn();
    const c = new TenantAIClient(ai as any, "acme", meter);
    const out = await c.run("@cf/meta/llama-3-8b-instruct", { prompt: "hi" });
    expect(out).toEqual({ response: "hi" });
    expect(ai.run).toHaveBeenCalledWith("@cf/meta/llama-3-8b-instruct", { prompt: "hi" });
    expect(meter).toHaveBeenCalledTimes(1);
    const meta = meter.mock.calls[0][0];
    expect(meta.tenant_id).toBe("acme");
    expect(meta.model).toBe("@cf/meta/llama-3-8b-instruct");
    expect(typeof meta.ms_latency).toBe("number");
  });

  it("extracts usage from response when present", async () => {
    const ai = mockAi({ usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 } });
    const meter = vi.fn();
    const c = new TenantAIClient(ai as any, "acme", meter);
    await c.run("@cf/meta/llama-3-8b-instruct", { prompt: "hi" });
    expect(meter.mock.calls[0][0].usage).toEqual({
      prompt_tokens: 10, completion_tokens: 20, total_tokens: 30,
    });
  });

  it("calls onMeter on FAILURE too (failed expensive call still attributes)", async () => {
    const ai = mockAi();
    (ai.run as any).mockRejectedValueOnce(new Error("upstream"));
    const meter = vi.fn();
    const c = new TenantAIClient(ai as any, "acme", meter);
    await expect(c.run("@cf/meta/llama-3-8b-instruct", { prompt: "hi" })).rejects.toMatchObject({
      code: "INFERENCE_FAILED",
    });
    expect(meter).toHaveBeenCalledTimes(1);
  });

  it("metering failure does NOT break inference (swallowed)", async () => {
    const ai = mockAi({ response: "ok" });
    const meter = vi.fn(() => {
      throw new Error("metronome down");
    });
    const c = new TenantAIClient(ai as any, "acme", meter);
    const out = await c.run("@cf/meta/llama-3-8b-instruct", { prompt: "hi" });
    expect(out).toEqual({ response: "ok" }); // inference succeeded even though meter threw
  });

  it("works without onMeter (optional)", async () => {
    const ai = mockAi({ response: "ok" });
    const c = new TenantAIClient(ai as any, "acme");
    const out = await c.run("@cf/meta/llama-3-8b-instruct", { prompt: "hi" });
    expect(out).toEqual({ response: "ok" });
  });
});
