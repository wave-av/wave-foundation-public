// types.ts
//
// Anthropic per-tenant attribution types. Anthropic has no native tenant primitive — the
// wrapper attributes usage by emitting a metered event tagged with tenant_id on every call.

export type TenantId = string;

export interface AnthropicUsage {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
}

export interface AnthropicAttributionEvent {
  tenant_id: TenantId;
  model: string;
  endpoint: "messages";
  request_id: string;
  /** True if Anthropic returned a non-2xx; usage may be 0. */
  error: boolean;
  /** Anthropic HTTP status code. */
  status: number;
  /** Wall-clock ms. */
  duration_ms: number;
  usage: AnthropicUsage;
  /** RFC3339 timestamp at call START. */
  started_at: string;
}

export type AnthropicErrorCode =
  | "INVALID_TENANT_ID"
  | "INVALID_API_KEY"
  | "INVALID_MODEL"
  | "INVALID_REQUEST"
  | "UNAUTHORIZED"
  | "RATE_LIMITED"
  | "ANTHROPIC_ERROR"
  | "FETCH_FAILED";

export class AnthropicAttributionError extends Error {
  constructor(
    message: string,
    public readonly code: AnthropicErrorCode,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "AnthropicAttributionError";
  }
}

export type AttributionSink = (event: AnthropicAttributionEvent) => void | Promise<void>;
