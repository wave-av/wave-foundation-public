# Cloudflare Workers AI Per-Tenant Attribution

Tenant-tagged wrapper for CF Workers AI inference (LLM, embedding, image). Hooks a `onMeter` callback so every call attributes to a tenant — feed into A5 cf-analytics-engine-platform for queries and/or A14 metronome-tenant-customer for billing.

## Pattern

```ts
const aiClient = new TenantAIClient(env.AI, tenant_id, async (meta) => {
  writeTenantEvent(env.ANALYTICS, {
    tenant_id: meta.tenant_id,
    extra_indexes: ["ai_inference", meta.model],
    blobs: [meta.ms_latency],
    doubles: [meta.usage?.total_tokens ?? 0],
  });
});
const out = await aiClient.run("@cf/meta/llama-3-8b-instruct", { prompt: "hi" });
```

## Why a wrapper (not direct binding use)

- **Latency tracking** by default (one extra `Date.now()` call).
- **Usage extraction** from the model response (where available).
- **Metering hook** runs on success AND failure (so failed expensive calls still attribute).
- **Failure-isolation**: metering exceptions never break inference (they're swallowed).

## Usage

```ts
import { TenantAIClient } from "@wave-av/foundation/frameworks/cf-workers-ai-tenant";
import { writeTenantEvent } from "@wave-av/foundation/frameworks/cf-analytics-engine-platform";

export default {
  async fetch(req: Request, env: { AI: AiBinding; ANALYTICS: any }) {
    const tenant_id = req.headers.get("x-wave-tenant-id") ?? "anon";
    const ai = new TenantAIClient(env.AI, tenant_id, async (meta) => {
      writeTenantEvent(env.ANALYTICS, {
        tenant_id: meta.tenant_id,
        extra_indexes: ["ai", meta.model],
        doubles: [meta.ms_latency, meta.usage?.total_tokens ?? 0],
      });
    });
    const result = await ai.run("@cf/meta/llama-3-8b-instruct", { prompt: "hi" });
    return Response.json(result);
  },
};
```

## Test plan

```bash
npx vitest run frameworks/cf-workers-ai-tenant
```

## Refs

- Task #197
- Pairs with A5 cf-analytics-engine-platform (sink for attribution events)
- Pairs with A14 metronome-tenant-customer (sink for billing meters)
- Pairs with A16/A17 (anthropic/openrouter attribution — sister wrappers for non-CF LLM paths)
