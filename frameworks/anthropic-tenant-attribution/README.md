# Anthropic Per-Tenant Attribution

Wrap the Anthropic Messages API with per-tenant usage attribution. Anthropic has no native
tenant primitive — attribution lives in WAVE's metering layer.

## Pattern

```ts
new TenantAnthropicClient(tenantId, apiKey, attributionSink) -> { messages(params) }
```

Every `messages()` call:
1. Validates `tenant_id` + `model` regex.
2. Wall-clock times the call.
3. Emits an `AnthropicAttributionEvent` to the sink — on **success AND failure**.
4. Swallows sink errors (never breaks inference because metering broke).

## Usage

```ts
import { TenantAnthropicClient } from "@wave-av/foundation/frameworks/anthropic-tenant-attribution";
import { ingestUsageEvents } from "@wave-av/foundation/frameworks/metronome-tenant-customer";

const client = new TenantAnthropicClient(
  "acme",
  env.ANTHROPIC_API_KEY,
  async (ev) => {
    await ingestUsageEvents(env.METRONOME_API_KEY, [{
      customer_id: tenant.metronome_customer_id,
      event_type: "wave.llm.input_tokens",
      timestamp: ev.started_at,
      transaction_id: `wave:${ev.tenant_id}:anthropic:${ev.request_id}`,
      properties: {
        model: ev.model,
        input_tokens: String(ev.usage.input_tokens),
        output_tokens: String(ev.usage.output_tokens),
        cache_read: String(ev.usage.cache_read_input_tokens ?? 0),
        cache_create: String(ev.usage.cache_creation_input_tokens ?? 0),
        error: ev.error ? "1" : "0",
        status: String(ev.status),
        duration_ms: String(ev.duration_ms),
      },
    }]);
  },
);

const reply = await client.messages({
  model: "claude-sonnet-4-5",
  max_tokens: 1024,
  messages: [{ role: "user", content: "Summarize this transcript" }],
});
```

## Failure attribution

If Anthropic returns 429 or 500, the wrapper still emits a metering event with `error: true`,
`usage: { input_tokens: 0, output_tokens: 0 }`, and the actual `status` + `duration_ms`. This
ensures retries don't go uncounted and that failure rates are observable per-tenant.

If `fetch()` itself throws (network failure), a metering event with `status: 0, error: true` is
emitted BEFORE the error propagates.

If the sink throws, the error is swallowed — inference must never break because metering broke.

## Security

- `tenant_id` matches `/^[a-zA-Z0-9_-]{1,64}$/`.
- `model` matches `/^claude-[a-z0-9-]+$/` — blocks injection via model field.
- `api_key` must start with `sk-` and be ≥20 chars (Anthropic format).
- `messages` array must be non-empty.

## Test plan

```bash
npx vitest run frameworks/anthropic-tenant-attribution
```

## Refs

- Task #202
- Pairs with A14 metronome-tenant-customer (sink target)
- Pairs with A17 openrouter-tenant-attribution (alt routing)
- Anti-thrash invariant from A11 cf-workers-ai-tenant
