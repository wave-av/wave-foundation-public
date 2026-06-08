// types.ts
//
// OpenRouter per-tenant attribution types. OpenRouter is OpenAI-compatible /v1/chat/completions
// but exposes per-call cost in USD, which we propagate to Metronome alongside token counts.

export type TenantId = string;

export interface OpenRouterUsage {
  prompt_tokens: number;
  completion_tokens: number;
  total_tokens: number;
  /** OpenRouter-specific: total cost in USD. May be 0 for free models. */
  cost_usd: number;
}

export interface OpenRouterAttributionEvent {
  tenant_id: TenantId;
  /** OpenRouter model slug, e.g. "anthropic/claude-sonnet-4-5" */
  model: string;
  endpoint: "chat/completions";
  /** OpenRouter response id, or "" on fetch failure. */
  response_id: string;
  error: boolean;
  status: number;
  duration_ms: number;
  usage: OpenRouterUsage;
  started_at: string;
}

export type OpenRouterErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_API_KEY"
  | "INVALID_MODEL"
  | "INVALID_REQUEST"
  | "UNAUTHORIZED"
  | "RATE_LIMITED"
  | "OPENROUTER_ERROR"
  | "FETCH_FAILED";

export class OpenRouterAttributionError extends Error {
  constructor(
    message: string,
    public readonly code: OpenRouterErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "OpenRouterAttributionError";
  }
}

export type AttributionSink = (event: OpenRouterAttributionEvent) => void | Promise<void>;
