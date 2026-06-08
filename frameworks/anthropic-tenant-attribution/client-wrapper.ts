// client-wrapper.ts
//
// TenantAnthropicClient wraps Anthropic Messages API. Every call:
//   1. validates tenant_id + model shape
//   2. times the call (wall-clock)
//   3. emits an AnthropicAttributionEvent to the sink — on success AND failure
//   4. swallows sink failures (never break inference because metering broke)
//
// Failed calls still emit metering so failed expensive prompts attribute correctly —
// same invariant as A11 Workers AI.

import {
  AnthropicAttributionError,
  AnthropicAttributionEvent,
  AnthropicUsage,
  AttributionSink,
  TenantId,
} from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const MODEL_REGEX = /^claude-[a-z0-9-]+$/;
const ANTHROPIC_API_BASE = "https://api.anthropic.com/v1";
const ANTHROPIC_VERSION = "2023-06-01";

export interface MessagesParams {
  model: string;
  max_tokens: number;
  messages: ReadonlyArray<{ role: "user" | "assistant"; content: string | unknown }>;
  system?: string | unknown;
  temperature?: number;
  /** Any additional Anthropic-supported fields. */
  [k: string]: unknown;
}

export interface MessagesResult {
  id: string;
  type: "message";
  role: "assistant";
  content: unknown;
  model: string;
  stop_reason: string | null;
  usage: AnthropicUsage;
}

export class TenantAnthropicClient {
  constructor(
    public readonly tenantId: TenantId,
    private readonly apiKey: string,
    private readonly sink: AttributionSink,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {
    if (!TENANT_ID_REGEX.test(tenantId)) {
      throw new AnthropicAttributionError("invalid tenant_id", "INVALID_TENANT_ID");
    }
    if (!apiKey || apiKey.length < 20 || !apiKey.startsWith("sk-")) {
      throw new AnthropicAttributionError("invalid api_key", "INVALID_API_KEY");
    }
  }

  async messages(params: MessagesParams): Promise<MessagesResult> {
    if (!MODEL_REGEX.test(params.model)) {
      throw new AnthropicAttributionError(`invalid model ${params.model}`, "INVALID_MODEL");
    }
    if (!Array.isArray(params.messages) || params.messages.length === 0) {
      throw new AnthropicAttributionError("messages must be non-empty", "INVALID_REQUEST");
    }
    if (!Number.isInteger(params.max_tokens) || params.max_tokens < 1) {
      throw new AnthropicAttributionError("max_tokens must be positive int", "INVALID_REQUEST");
    }

    const started_at = new Date().toISOString();
    const t0 = Date.now();
    let status = 0;
    let usage: AnthropicUsage = { input_tokens: 0, output_tokens: 0 };
    let request_id = "";
    let result: MessagesResult | null = null;
    let errCode: "UNAUTHORIZED" | "RATE_LIMITED" | "ANTHROPIC_ERROR" | "FETCH_FAILED" | null =
      null;

    try {
      const res = await this.fetchImpl(`${ANTHROPIC_API_BASE}/messages`, {
        method: "POST",
        headers: {
          "x-api-key": this.apiKey,
          "anthropic-version": ANTHROPIC_VERSION,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(params),
      });
      status = res.status;
      request_id = res.headers.get("request-id") ?? "";

      if (!res.ok) {
        errCode =
          status === 401 ? "UNAUTHORIZED" : status === 429 ? "RATE_LIMITED" : "ANTHROPIC_ERROR";
      } else {
        result = (await res.json()) as MessagesResult;
        if (result.usage) usage = result.usage;
      }
    } catch (err) {
      errCode = "FETCH_FAILED";
      await this.emit({
        tenant_id: this.tenantId,
        model: params.model,
        endpoint: "messages",
        request_id,
        error: true,
        status: 0,
        duration_ms: Date.now() - t0,
        usage,
        started_at,
      });
      throw new AnthropicAttributionError("anthropic fetch failed", errCode, err);
    }

    await this.emit({
      tenant_id: this.tenantId,
      model: params.model,
      endpoint: "messages",
      request_id,
      error: errCode !== null,
      status,
      duration_ms: Date.now() - t0,
      usage,
      started_at,
    });

    if (errCode) {
      throw new AnthropicAttributionError(`anthropic ${status}`, errCode);
    }
    return result as MessagesResult;
  }

  private async emit(event: AnthropicAttributionEvent): Promise<void> {
    try {
      await this.sink(event);
    } catch {
      // never break inference because metering broke
    }
  }
}
