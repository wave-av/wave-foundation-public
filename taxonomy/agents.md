# Agent Taxonomy

Agents are classified on **two orthogonal axes**: domain (what they work on) and model tier
(what model/cost they run at). Both live in agent frontmatter.

## Axis 1 — Domain (`category:`)

Grounded in the real distribution across the harvested agent corpus:

`infrastructure`, `backend`, `ai`, `streaming`, `monitoring`, `analytics`, `security`,
`testing`, `integration`, `payments`, `database`, `orchestration`, `frontend`,
`documentation`, `api`, `compliance`, `devops`.

Normalize known duplicates: `integrations` → `integration`, `ai-ml` → `ai`.

## Axis 2 — Model tier (`model:`)

| Tier | When |
|------|------|
| `haiku` | Read-only / lookup / simple classification (cheapest) |
| `sonnet` | Standard implementation, review, most agents (default) |
| `opus` | Security, compliance, complex multi-step reasoning |

### Optional routing tier (local-first deployments)

Projects with local inference (e.g., Ollama on a workstation) add a routing tier:
`local_speed_tier`, `local_quality_tier`, `sonnet_tier`, `opus_tier`, `non_executable`.
Each routed agent carries a `justification` and `current_model`. This tier is
deployment-specific (not all consumers have local inference) — keep it in the project's
routing map, not in the agent definition.

## Convention

- Every agent declares `category` (∈ domain set) and `model` (∈ haiku/sonnet/opus).
- One objective per agent spawn.
- Read-only agents → `haiku`; code-writers → `sonnet`; security/compliance → `opus`.
