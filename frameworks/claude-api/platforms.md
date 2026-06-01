# Cloud Platforms

Where Claude runs, what the model ID looks like, and which features survive the trip.
Four commercial surfaces serve the same Messages API shape but differ in **who operates the
inference stack**, the **model-ID format**, and **feature parity**. WAVE never calls any of these
directly from code — they sit behind the [model-routing Leveragizer](../model-routing/README.md)
(tier 4 `direct`). This file is the source of truth for *which* surface a routing profile pins to.

Default model is **`claude-opus-4-8`** everywhere (exact string, never date-suffix an alias);
`claude-sonnet-4-6` balanced, `claude-haiku-4-5` fast. Only the *prefix* changes per platform.

## The four surfaces at a glance

| Surface | Operator | Model ID | API surface | Base URL | SDK client |
|---|---|---|---|---|---|
| **Claude API** (first-party) | Anthropic | `claude-opus-4-8` | `/v1/{endpoint}` | `api.anthropic.com` | `Anthropic` |
| **Claude Platform on AWS** | **Anthropic** (AWS = auth+billing) | `claude-opus-4-8` (bare) | Claude API `/v1/{endpoint}` | `aws-external-anthropic.{region}.api.aws` | `AnthropicAWS` (beta) |
| **Amazon Bedrock** | **AWS** | `anthropic.claude-opus-4-8` | Messages `/anthropic/v1/messages` | `bedrock-mantle.{region}.api.aws` | `AnthropicBedrockMantle` |
| **Vertex AI** | Google | `claude-opus-4-8` (in URL, not body) | `:streamRawPredict` | `{loc}-aiplatform.googleapis.com` | `AnthropicVertex` |
| **Microsoft Foundry** | Anthropic (Azure = billing), preview | `claude-opus-4-8` (= deployment name) | Messages `/anthropic/v1/messages` | `{resource}.services.ai.azure.com/anthropic` | `AnthropicFoundry` |

> **Bedrock legacy** (`InvokeModel`/`Converse`, ARN IDs like `anthropic.claude-opus-4-8-v1`,
> EventStream framing) is a separate, older surface — migrate to `bedrock-mantle` Messages.

## Model-ID format rules

| Platform | Format | Example |
|---|---|---|
| Claude Platform on AWS | **bare**, identical to first-party | `claude-opus-4-8` |
| Amazon Bedrock | `anthropic.` prefix | `anthropic.claude-opus-4-8` |
| Vertex AI | bare, **in the endpoint URL** (`anthropic_version` in body = `vertex-2023-10-16`) | `.../models/claude-opus-4-8:streamRawPredict` |
| Microsoft Foundry | bare = the **deployment name** you chose (defaults to model ID) | `claude-opus-4-8` |

Vertex pins some legacy IDs with `@date` (e.g. `claude-sonnet-4-5@20250929`) — current-gen
(`opus-4-8/4-7/4-6`, `sonnet-4-6`) are bare. Vertex lifecycle dates are set by Google **independently**
of Anthropic's deprecation schedule.

## Feature parity matrix

| Capability | Claude Platform on AWS | Amazon Bedrock | Vertex AI | Microsoft Foundry |
|---|:---:|:---:|:---:|:---:|
| Messages API | ✅ | ✅ | ✅ | ✅ |
| Extended thinking | ✅ | ✅ | ✅ | ✅ |
| Prompt caching | ✅ | ✅ | ✅ | ✅ |
| Tool use (bash/computer/memory/text-editor) | ✅ | ✅ | ✅ | ✅ |
| Citations / Structured outputs | ✅ | ✅ | ✅ | ✅ |
| Streaming | ✅ SSE | ✅ SSE | ✅ | ✅ |
| Server tools (code-exec/web-fetch/advisor) | ✅ | ❌ | ⚠️ web-search only | ⚠️ see overview |
| Files API / URL input sources | ✅ | ❌ | ❌ | ⚠️ see overview |
| **Agent Skills** | ✅ (beta) | ❌ (needs code-exec) | ❌ | ⚠️ |
| **Claude Managed Agents** | ✅ (full) | ❌ | ❌ | ⚠️ |
| **Self-hosted sandboxes** | ⚠️ except work-list endpoint | ❌ | ❌ | ❌ |
| Message Batches API | ✅ | ❌ | ❌ | ❌ |
| Beta features (`anthropic-beta` header) | ✅ pass-through | ❌ header ignored | partial | partial |
| Admin / Usage / Cost / Models API | ⚠️ workspaces only | ❌ | ❌ | ❌ |
| MCP connector / tunnels | ⚠️ public MCP only | ❌ | ❌ | ⚠️ |
| Fast mode / OpenAI-compat endpoints | ❌ | ❌ | ❌ | ❌ |

The `usage` object (incl. `cache_read_input_tokens`) is **identical across all five surfaces** — verify
caching the same way everywhere.

### Context-window gotcha (load-bearing)

1M-token context is **not uniform** across surfaces — confirm per platform before sizing prompts:

| Model | Claude API / AWS | Vertex AI | Microsoft Foundry |
|---|:---:|:---:|:---:|
| Opus 4.8 | 1M (per first-party) | **1M** | **200k at launch** |
| Opus 4.7 / 4.6, Sonnet 4.6 | 1M | 1M | 1M |
| Sonnet 4.5 and older | 200k | 200k | 200k |

> ⚠️ **Foundry caps Opus 4.8 at 200k at launch** even though 4.7/4.6 get 1M there. Do not assume the
> newest model has the largest window on every surface. Vertex also enforces a **30 MB payload limit**.

## Feature-tuning behavior is platform-independent

Per-model parameter rules (these are model properties, not platform properties — they hold on every surface):

- **Opus 4.8/4.7:** thinking is **adaptive only** (`thinking.budget_tokens` → 400; `temperature`/`top_p`/`top_k` → 400). Reasoning depth is set via `output_config.effort` (`low|medium|high`, default `high`; `xhigh`/`max` Opus-only). `effort` **errors on `haiku-4-5`**. `thinking.display` = `omitted|summarized`.
- **Last-assistant prefill** → 400 on `opus-4.8/4.7/4.6` + `sonnet-4.6`; use `output_config.format` (the `output_format` field is deprecated).
- **Caching:** prefix-match, `cache_control: ephemeral`, top-level auto-cache, max 4 breakpoints. Min cacheable prefix: **opus-4-8 = 1024** (live-doc authoritative — an older cached table said 4096; treat 1024 as current and flag if a platform rejects it), sonnet-4-6 = 1024, haiku-4-5 = 4096. Pricing: read **0.1x**, 5m write **1.25x**, 1h write **2x**.
- **Stream when `max_tokens > 16000`** (long generations on any surface).

## ZDR + data residency by surface

| Surface | Inference data processor | ZDR | Residency control |
|---|---|---|---|
| Claude Platform on AWS | **Anthropic** | opt-in (contact rep) | `inference_geo` per request (`us` 1.1x / `global`); Opus 4.6+ / Sonnet 4.6+ only |
| Amazon Bedrock | **AWS** (zero Anthropic operator access) | governed by AWS (Anthropic ZDR n/a) | Global vs Regional endpoint (+10% regional); inference profiles US/EU/JP/AU |
| Vertex AI | Google | governed by Google Cloud | global / multi-region (`us`,`eu`) / regional (+10%) |
| Microsoft Foundry | **Anthropic** (preview) | available | Global Standard deployment at launch |

- **Batch API = 50% off but NOT ZDR-eligible.** Prompt caching **IS** ZDR-eligible. Pick one when ZDR is mandatory.
- **Regulated / sole-AWS-processor (FedRAMP High, IL4/5, HIPAA-ready):** use **Amazon Bedrock**, the only surface where AWS is the sole operator. Claude Platform on AWS does **not** offer HIPAA readiness.

## When WAVE would pick each (routing-profile guidance)

| Pick | When | Why |
|---|---|---|
| **First-party Claude API** | default tier-4 fallback today | simplest, full feature set, same-day models |
| **Claude Platform on AWS** | WAVE workloads anchored in AWS that still need **Skills / Managed Agents / Batch / beta headers** | Anthropic-operated → near-full parity + same-day models, billed via AWS Marketplace, SigV4/IAM auth |
| **Amazon Bedrock** | compliance floor: FedRAMP/IL/HIPAA, **AWS-sole-processor** mandate, VPC-internal | zero Anthropic operator access; accept the feature loss (no batch/files/skills/managed-agents) |
| **Vertex AI** | GCP-anchored spokes; need 1M context on Opus 4.8 + web-search server tool | Google-operated, 1M ctx for current-gen, but no skills/managed-agents/batch |
| **Microsoft Foundry** | Azure-billed customers / Entra-ID RBAC shops | Anthropic-operated preview; **watch the 200k Opus-4.8 cap** + no Go/Ruby SDK + no batch/admin |

For our own infra: **route through the gateway**, set the platform on the routing *profile* (not in
call sites). Sovereign/USER traffic still starts at tier-1 local (Mac Studio) per the Leveragizer.

## Anti-patterns

- ❌ Hardcoding a model ID **or** a platform base URL in code — both live in routing config (the gateway picks the surface).
- ❌ Calling any cloud surface directly, bypassing tier-2 gateway (loses observability, billing aggregation, retry policy).
- ❌ Date-suffixing the default alias (`claude-opus-4-8-2025...`) — current-gen IDs are bare on AWS/Vertex/Foundry; only legacy Vertex IDs use `@date`.
- ❌ Forgetting the `anthropic.` prefix on Bedrock, or putting `model` in the **body** on Vertex (it goes in the URL).
- ❌ Assuming 1M context on Foundry Opus 4.8 (it's **200k at launch**) or assuming a `>30MB` payload works on Vertex.
- ❌ Sending `anthropic-beta` headers to Bedrock/legacy (silently ignored) or expecting Skills/Managed-Agents/Batch there.
- ❌ Combining **Batch (50% off)** with a **ZDR-required** workload — batch isn't ZDR-eligible; use prompt caching instead.
- ❌ Omitting `anthropic-workspace-id` on Claude Platform on AWS, or skipping the one-time `aws iam enable-outbound-web-identity-federation`.

## Env vars

| Var | Surface | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | first-party | tier-4 direct fallback |
| `ANTHROPIC_AWS_WORKSPACE_ID` | Claude Platform on AWS | required `anthropic-workspace-id` header |
| `ANTHROPIC_AWS_API_KEY` | Claude Platform on AWS | API-key auth (alt to SigV4) |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | AWS + Bedrock | endpoint region (AWS surface raises if unset — **no default**) |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` | AWS + Bedrock | SigV4 credential chain |
| `ANTHROPIC_VERTEX_PROJECT_ID` / region arg | Vertex AI | GCP project + `global`/`us`/`eu`/region |
| `ANTHROPIC_FOUNDRY_API_KEY` | Foundry | API key |
| `ANTHROPIC_FOUNDRY_RESOURCE` / `ANTHROPIC_FOUNDRY_BASE_URL` | Foundry | resource name **xor** full base URL |

## Code: same request, four prefixes

```python
# Claude Platform on AWS — bare ID, Anthropic-operated, full parity
from anthropic import AnthropicAWS
AnthropicAWS().messages.create(  # reads AWS_REGION + ANTHROPIC_AWS_WORKSPACE_ID
    model="claude-opus-4-8", max_tokens=1024,
    messages=[{"role": "user", "content": "Hi"}])

# Amazon Bedrock — anthropic. prefix, AWS-operated
from anthropic import AnthropicBedrockMantle
AnthropicBedrockMantle(aws_region="us-east-1").messages.create(
    model="anthropic.claude-opus-4-8", max_tokens=1024,
    messages=[{"role": "user", "content": "Hi"}])

# Vertex AI — model in URL via SDK; anthropic_version handled by client
from anthropic import AnthropicVertex
AnthropicVertex(project_id="MY_PROJECT_ID", region="global").messages.create(
    model="claude-opus-4-8", max_tokens=1024,
    messages=[{"role": "user", "content": "Hi"}])

# Microsoft Foundry — model = deployment name (200k ctx on Opus 4.8 at launch)
from anthropic import AnthropicFoundry
AnthropicFoundry(resource="example-resource").messages.create(
    model="claude-opus-4-8", max_tokens=1024,
    messages=[{"role": "user", "content": "Hi"}])
```

```bash
# Claude Platform on AWS (SigV4) — workspace header + federation enabled once per account
curl "https://aws-external-anthropic.us-west-2.api.aws/v1/messages" \
  --aws-sigv4 "aws:amz:us-west-2:aws-external-anthropic" \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "x-amz-security-token: $AWS_SESSION_TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-workspace-id: $ANTHROPIC_AWS_WORKSPACE_ID" \
  -d '{"model":"claude-opus-4-8","max_tokens":1024,
       "inference_geo":"us","messages":[{"role":"user","content":"Hi"}]}'

# Amazon Bedrock (SigV4, anthropic. prefix, service=bedrock-mantle)
curl "https://bedrock-mantle.us-east-1.api.aws/anthropic/v1/messages" \
  --aws-sigv4 "aws:amz:us-east-1:bedrock-mantle" \
  --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"anthropic.claude-opus-4-8","max_tokens":1024,
       "messages":[{"role":"user","content":"Hi"}]}'
```

## Related

- [`../model-routing/README.md`](../model-routing/README.md) — the gateway picks the surface; never bypass it
- [`./model-matrix.md`](./model-matrix.md) — per-model parameter constraints (thinking/effort/prefill)
- [`./batch.md`](./batch.md) — 50%-off batch + the not-ZDR gate

## Sources

- `build-with-claude/claude-platform-on-aws.md`
- `build-with-claude/claude-in-amazon-bedrock.md`
- `build-with-claude/claude-on-vertex-ai.md`
- `build-with-claude/claude-in-microsoft-foundry.md`
- `build-with-claude/claude-on-amazon-bedrock-legacy.md` (referenced for legacy delta)
