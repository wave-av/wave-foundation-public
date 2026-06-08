// Shared types for Cloudflare Workers AI per-tenant attribution.
// Workers AI is CF's edge LLM/embedding/image inference. For for-Platforms, we wrap the binding
// to (a) tag every call with tenant_id for Analytics Engine attribution and (b) meter usage
// against the tenant's Metronome customer (A14).

export type TenantId = string;

export interface InferenceCallMetadata {
  tenant_id: TenantId;
  model: string;
  ms_latency: number;
  // Provided when the model returns usage stats (tokens for LLMs, etc.)
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
    total_tokens?: number;
  };
}

export class WorkersAITenantError extends Error {
  constructor(message: string, public readonly code: string, public readonly cause?: unknown) {
    super(message);
    this.name = "WorkersAITenantError";
  }
}
