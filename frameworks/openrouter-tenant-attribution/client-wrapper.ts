// client-wrapper.ts
//
// TenantOpenRouterClient wraps OpenRouter /v1/chat/completions (OpenAI-compatible).
// Same anti-thrash invariant as A11/A16: every call emits a metering event including
// failures and fetch-throws; sink errors swallowed.

import {
  AttributionSink,
  OpenRouterAttributionError,
  OpenRouterAttributionEvent,
  OpenRouterUsage,
  TenantId,
} from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
// OpenRouter model slug: provider/name pattern, e.g. "anthropic/claude-sonnet-4-5".
const MODEL_REGEX = /^[a-z0-9]+(?:-[a-z0-9]+)*\/[a-zA-Z0-9._-]+$/;
const OPENROUTER_API_BASE = "https://openrouter.ai/api/v1";

export interface ChatParams {
  model: string;
  messages: ReadonlyArray<{ role: "system" | "user" | "assistant"; content: string }>;
  max_tokens?: number;
  temperature?: number;
  /** Wave per-call idempotency key, propagated as a header for OpenRouter dedupe. */
  transaction_id?: string;
  [k: string]: unknown;
}

export interface ChatResult {
  id: string;
  model: string;
  choices: Array<{ index: number; message: { role: string; content: string }; finish_reason: string | null }>;
  usage?: { prompt_tokens?: number; completion_tokens?: number; total_tokens?: number; cost?: number };
}

export class TenantOpenRouterClient {
  constructor(
    public readonly tenantId: TenantId,
    private readonly apiKey: string,
    private readonly sink: AttributionSink,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {
    if (!TENANT_ID_REGEX.test(tenantId)) {
      throw new OpenRouterAttributionError("invalid tenant_id", "INVALID_TENANT_ID");
    }
    if (!apiKey || apiKey.length < 20 || !apiKey.startsWith("sk-or-")) {
      throw new OpenRouterAttributionError("invalid api_key", "INVALID_API_KEY");
    }
  }

  async chat(params: ChatParams): Promise<ChatResult> {
    if (!MODEL_REGEX.test(params.model)) {
      throw new OpenRouterAttributionError(`invalid model ${params.model}`, "INVALID_MODEL");
    }
    if (!Array.isArray(params.messages) || params.messages.length === 0) {
      throw new OpenRouterAttributionError("messages must be non-empty", "INVALID_REQUEST");
    }

    const started_at = new Date().toISOString();
    const t0 = Date.now();
    let status = 0;
    let response_id = "";
    let usage: OpenRouterUsage = {
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
      cost_usd: 0,
    };
    let result: ChatResult | null = null;
    let errCode: "UNAUTHORIZED" | "RATE_LIMITED" | "OPENROUTER_ERROR" | "FETCH_FAILED" | null =
      null;

    const headers: Record<string, string> = {
      "Authorization": `Bearer ${this.apiKey}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://wave.online",
      "X-Title": "WAVE",
    };
    if (params.transaction_id) headers["X-Transaction-Id"] = params.transaction_id;

    try {
      const res = await this.fetchImpl(`${OPENROUTER_API_BASE}/chat/completions`, {
        method: "POST",
        headers,
        body: JSON.stringify(params),
      });
      status = res.status;

      if (!res.ok) {
        errCode =
          status === 401 ? "UNAUTHORIZED" : status === 429 ? "RATE_LIMITED" : "OPENROUTER_ERROR";
      } else {
        result = (await res.json()) as ChatResult;
        response_id = result.id ?? "";
        if (result.usage) {
          usage = {
            prompt_tokens: result.usage.prompt_tokens ?? 0,
            completion_tokens: result.usage.completion_tokens ?? 0,
            total_tokens: result.usage.total_tokens ?? 0,
            cost_usd: typeof result.usage.cost === "number" ? result.usage.cost : 0,
          };
        }
      }
    } catch (err) {
      errCode = "FETCH_FAILED";
      await this.emit({
        tenant_id: this.tenantId,
        model: params.model,
        endpoint: "chat/completions",
        response_id,
        error: true,
        status: 0,
        duration_ms: Date.now() - t0,
        usage,
        started_at,
      });
      throw new OpenRouterAttributionError("openrouter fetch failed", errCode, err);
    }

    await this.emit({
      tenant_id: this.tenantId,
      model: params.model,
      endpoint: "chat/completions",
      response_id,
      error: errCode !== null,
      status,
      duration_ms: Date.now() - t0,
      usage,
      started_at,
    });

    if (errCode) {
      throw new OpenRouterAttributionError(`openrouter ${status}`, errCode);
    }
    return result as ChatResult;
  }

  private async emit(event: OpenRouterAttributionEvent): Promise<void> {
    try {
      await this.sink(event);
    } catch {
      // never break inference because metering broke
    }
  }
}
