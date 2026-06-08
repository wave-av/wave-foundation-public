# OpenRouter Per-Tenant Attribution

Wrap OpenRouter `/v1/chat/completions` (OpenAI-compatible) with per-tenant usage + cost attribution.

## Pattern

```ts
new TenantOpenRouterClient(tenantId, apiKey, attributionSink) -> { chat(params) }
```

Every `chat()` call:
1. Validates `tenant_id` + model slug regex.
2. Sets `HTTP-Referer: https://wave.online` + `X-Title: WAVE` so OpenRouter's dashboards group WAVE traffic.
3. Forwards `transaction_id` as `X-Transaction-Id` header for OpenRouter retries dedupe.
4. Wall-clock times the call.
5. Emits an `OpenRouterAttributionEvent` (with `cost_usd`) on success AND failure.

## Why OpenRouter alongside Anthropic-direct?

OpenRouter routes to 100+ models with one key, and exposes **per-call USD cost** in the response.
Anthropic-direct gives raw token counts and we'd have to maintain a token→USD pricing table.
OpenRouter's `usage.cost` field lets us pass the actual USD to Metronome with no pricing logic
in WAVE infra.

## Usage

```ts
import { TenantOpenRouterClient } from "@wave-av/foundation/frameworks/openrouter-tenant-attribution";
import { ingestUsageEvents } from "@wave-av/foundation/frameworks/metronome-tenant-customer";

const client = new TenantOpenRouterClient(
  "acme",
  env.OPENROUTER_API_KEY,
  async (ev) => {
    await ingestUsageEvents(env.METRONOME_API_KEY, [{
      customer_id: tenant.metronome_customer_id,
      event_type: "wave.llm.cost_usd",
      timestamp: ev.started_at,
      transaction_id: `wave:${ev.tenant_id}:openrouter:${ev.response_id}`,
      properties: {
        model: ev.model,
        prompt_tokens: String(ev.usage.prompt_tokens),
        completion_tokens: String(ev.usage.completion_tokens),
        cost_usd: String(ev.usage.cost_usd),
        error: ev.error ? "1" : "0",
        status: String(ev.status),
        duration_ms: String(ev.duration_ms),
      },
    }]);
  },
);

const reply = await client.chat({
  model: "anthropic/claude-sonnet-4-5",
  messages: [{ role: "user", content: "Hello" }],
  transaction_id: "wave:acme:chat:abc123",
});
```

## Failure attribution

Same anti-thrash invariant as A11/A16. Failures emit metering with `error: true`, retries
with the same `transaction_id` are safe.

## Security

- `tenant_id` regex `/^[a-zA-Z0-9_-]{1,64}$/`
- `model` regex `/^[a-z0-9]+(?:-[a-z0-9]+)*\/[a-zA-Z0-9._-]+$/` — enforces `provider/name` shape, blocks injection via model field
- `api_key` must start with `sk-or-` and be ≥20 chars (OpenRouter format)

## Test plan

```bash
npx vitest run frameworks/openrouter-tenant-attribution
```

## Refs

- Task #203
- Pairs with A16 anthropic-tenant-attribution (direct alt)
- Pairs with A14 metronome-tenant-customer (sink target)
