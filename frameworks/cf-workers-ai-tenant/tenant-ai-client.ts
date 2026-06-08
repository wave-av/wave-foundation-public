// tenant-ai-client.ts
//
// Wraps a CF Workers AI binding with tenant attribution.
//   - Every call is timed (ms_latency)
//   - Token usage (when present in the response) is extracted
//   - An optional onMeter() callback receives { tenant_id, model, ms_latency, usage } so the
//     caller can write to Analytics Engine (A5) and/or Metronome (A14) without coupling this
//     scaffold to either.

import { InferenceCallMetadata, TenantId, WorkersAITenantError } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
// CF model identifiers — strict: @cf/<provider>/<name> or <provider>/<name>
const MODEL_REGEX = /^@?[a-z0-9][a-z0-9_\-]*\/[a-zA-Z0-9._\-]+$/;

// CF Workers AI binding shape (subset).
export interface AiBinding {
  run<T = unknown>(model: string, inputs: Record<string, unknown>): Promise<T>;
}

export type MeterCallback = (meta: InferenceCallMetadata) => void | Promise<void>;

export class TenantAIClient {
  constructor(
    private readonly ai: AiBinding,
    private readonly tenant_id: TenantId,
    private readonly onMeter?: MeterCallback,
  ) {
    if (!TENANT_ID_REGEX.test(tenant_id)) {
      throw new WorkersAITenantError("invalid tenant_id", "INVALID_TENANT_ID");
    }
  }

  async run<T = unknown>(model: string, inputs: Record<string, unknown>): Promise<T> {
    if (!MODEL_REGEX.test(model)) {
      throw new WorkersAITenantError("invalid model identifier", "INVALID_MODEL");
    }
    const t0 = Date.now();
    let result: T;
    try {
      result = await this.ai.run<T>(model, inputs);
    } catch (err) {
      const ms_latency = Date.now() - t0;
      await this.safeOnMeter({ tenant_id: this.tenant_id, model, ms_latency });
      throw new WorkersAITenantError("ai inference failed", "INFERENCE_FAILED", err);
    }
    const ms_latency = Date.now() - t0;
    const usage = extractUsage(result as unknown);
    await this.safeOnMeter({ tenant_id: this.tenant_id, model, ms_latency, usage });
    return result;
  }

  private async safeOnMeter(meta: InferenceCallMetadata): Promise<void> {
    if (!this.onMeter) return;
    try {
      await this.onMeter(meta);
    } catch {
      // Never let attribution failures break the inference call. Failure on metering is logged
      // by the caller's onMeter implementation, not propagated.
    }
  }
}

function extractUsage(result: unknown): InferenceCallMetadata["usage"] | undefined {
  if (!result || typeof result !== "object") return undefined;
  const r = result as Record<string, unknown>;
  const u = (r["usage"] ?? r["meta"]) as Record<string, unknown> | undefined;
  if (!u) return undefined;
  return {
    prompt_tokens: typeof u.prompt_tokens === "number" ? u.prompt_tokens : undefined,
    completion_tokens: typeof u.completion_tokens === "number" ? u.completion_tokens : undefined,
    total_tokens: typeof u.total_tokens === "number" ? u.total_tokens : undefined,
  };
}
