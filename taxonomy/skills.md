# Skill Taxonomy

Skills are classified by a **category prefix** on the directory/`name` (Claude Code resolves
skills by directory, so `name` MUST equal the directory — enforced by `scripts/validate-skills.py`).

## Approved category prefixes (product-agnostic)

Grounded in the real distribution across the harvested skill corpus:

| Prefix | Domain |
|--------|--------|
| `ai-` | AI/LLM integrations (Claude, Gemini, OpenAI, vision, embeddings) |
| `streaming-` | Live/VOD streaming, protocols, broadcast |
| `infra-` | Infrastructure, scaling, edge/CDN, kubernetes |
| `platform-` | Platform capabilities (quotas, feature flags, white-label, SLA) |
| `security-` | Auth, RBAC, threat modeling, encryption |
| `monitoring-` | Observability (Sentry, Grafana, Dash0, SLO) |
| `dev-` | Developer workflow (code quality, refactoring, LSP, MCP) |
| `doc-` | Document processing (pdf, docx, xlsx, pptx) |
| `payments-` | Billing, Stripe, monetization, payouts |
| `compliance-` | SOC2/GDPR/HIPAA, governance, licensing, audit trail |
| `integration-` | Third-party services (Slack, GitHub, Resend, Upstash, …) |
| `events-` | Event-driven patterns (Inngest, webhooks, idempotency) |
| `perf-` | Performance (search, memory, video player, egress) |
| `agent-` | Agent operations (routing, replay, scheduling, tracing) |
| `analytics-` | Analytics, BI, dashboarding |
| `testing-` | Test strategy, QA, Playwright, CodeRabbit |
| `database-` | Database patterns, RLS, multi-region, operations |
| `workflow-` | Workflow patterns (TDD, EPCC, runner) |
| `context-` | Context management, gathering, compaction |
| `plan-` | Planning & decomposition (plan-generate/enhance/to-action/audit — shipped in `plugin/`) |

**Reserved internal prefixes:** `_core-` (core capabilities), `_external` (vendored third-party),
`_consolidated`, `_archived`.

**Product namespace:** `wave-` is **product-specific** (WAVE platform). It is NOT part of the
generic foundation taxonomy — `wave-*` skills stay with the product, not the foundation.

## Convention

- New skills SHOULD use an approved prefix. The validator emits an advisory warning for unknown
  prefixes (not a hard failure — the harvest contains legacy un-prefixed names being migrated).
- Description MUST be trigger-oriented ("Use when …"). See `schemas/skill-frontmatter.schema.json`.
- To add a prefix: propose it here first, then update the validator's approved set.
