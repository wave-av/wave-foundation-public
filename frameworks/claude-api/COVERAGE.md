# Coverage

The completeness proof for the Claude-API standard. Every page in Anthropic's own
`llms.txt` index (snapshot `/tmp/claude-docs-snapshot`, 2026-05-30) is enumerated below,
grouped by the five conceptual sections, and marked one of:

| Mark | Meaning |
|------|---------|
| ✅ `<file>.md` | Covered by that standard file in this dir |
| 🚫 N/A | Not applicable to WAVE — one-line reason given |
| 🔲 TODO `#N` | Not yet covered; task id from the program (see `TaskList`) |

WAVE does NOT re-document Anthropic. Each ✅ file states the **WAVE posture** on that
feature (route via the Leveragizer, never hardcode a model, caching mandatory, etc.).
This file lets a reader diff our coverage against Anthropic's index — re-run the
[Regenerate](#regenerate) recipe against a future index and the diff is the gap.

## Counts

| Section | Pages | ✅ Covered | 🚫 N/A | 🔲 TODO |
|---------|------:|-----------:|-------:|--------:|
| api (concept pages, SDK-lang variants collapsed) | 11 | 8 | 3 | 0 |
| build-with-claude | 32 | 27 | 5 | 0 |
| agents-and-tools | 39 | 26 | 13 | 0 |
| managed-agents | 22 | 0 | 1 | 21 |
| manage-claude | 25 | 12 | 13 | 0 |
| **Total** | **129** | **73** | **35** | **21** |

Per-language SDK reference pages under `api/` (cli/csharp/Go/Java/php/Python/Ruby/terraform/TypeScript
× every endpoint) are NOT counted as distinct surface — they are the same endpoint, and
[`request-surface.md`](./request-surface.md) declares Python+TypeScript as the only sanctioned
client SDKs. The 129 figure counts conceptual/endpoint pages, not the ~1,540 raw `llms.txt` lines.

## api/

| Page | Status | Note |
|------|--------|------|
| `overview.md` | ✅ [`README.md`](./README.md) | entry point; WAVE routes everything via gateway |
| `messages.md` + `messages/create.md` | ✅ [`request-surface.md`](./request-surface.md) | the one endpoint we call |
| `messages/count_tokens.md` | ✅ [`context-management.md`](./context-management.md) | cost/route planning |
| `messages/batches/*` (create/list/retrieve/results/cancel/delete) + `cancel-message-batches.md` | ✅ [`batch.md`](./batch.md) | 50% off, NOT ZDR-eligible |
| `models.md` + `models/{list,retrieve}.md` | ✅ [`model-matrix.md`](./model-matrix.md) | aliases only; never date-suffix |
| `errors.md` | ✅ [`request-surface.md`](./request-surface.md) | typed exceptions section |
| `rate-limits.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | per-workspace/-key limits |
| `service-tiers.md` | ✅ [`request-surface.md`](./request-surface.md) | priority/standard tier flag |
| `beta-headers.md` | ✅ [`tools.md`](./tools.md) | advisor-tool / fine-grained beta gates |
| `client-sdks.md` | ✅ [`request-surface.md`](./request-surface.md) | Python + TS sanctioned only |
| `versioning.md` | 🚫 N/A | gateway pins `anthropic-version`; spokes never set it directly |
| `supported-regions.md` | 🚫 N/A | gateway egresses from fixed region; not a spoke concern |
| `overview` (admin namespace `api/admin.md`) | 🚫 N/A | see manage-claude `admin-api.md` row |

## build-with-claude/

| Page | Status | Note |
|------|--------|------|
| `overview.md` | ✅ [`README.md`](./README.md) | feature index |
| `working-with-messages.md` | ✅ [`request-surface.md`](./request-surface.md) | message shape rules |
| `streaming.md` | ✅ [`request-surface.md`](./request-surface.md) | **stream when `max_tokens` > 16000** |
| `handling-stop-reasons.md` | ✅ [`request-surface.md`](./request-surface.md) + [`tools.md`](./tools.md) | `stop_reason` handling |
| `structured-outputs.md` | ✅ [`request-surface.md`](./request-surface.md) | `output_config.format`; `output_format` deprecated |
| `adaptive-thinking.md` | ✅ [`thinking-and-effort.md`](./thinking-and-effort.md) | Opus 4.8/4.7 adaptive-ONLY; `budget_tokens`→400 |
| `extended-thinking.md` | ✅ [`thinking-and-effort.md`](./thinking-and-effort.md) | legacy manual-budget context |
| `effort.md` | ✅ [`thinking-and-effort.md`](./thinking-and-effort.md) | `output_config.effort` low/med/high/max/xhigh; default high; xhigh+max Opus-only; ERRORS on haiku-4-5 |
| `task-budgets.md` (beta) | ✅ [`context-management.md`](./context-management.md) | beta budget caps |
| `fast-mode.md` (research preview) | ✅ [`model-matrix.md`](./model-matrix.md) | haiku-4-5 fast lane note |
| `prompt-caching.md` | ✅ [`prompt-caching.md`](./prompt-caching.md) | prefix-match; ephemeral; ≤4 breakpoints; min prefix **opus-4-8=1024** (live doc; older cached table said 4096 — flagged), sonnet-4-6=1024, haiku-4-5=4096; read 0.1x / 5m write 1.25x / 1h write 2x; ZDR-eligible |
| `cache-diagnostics.md` (beta) | ✅ [`prompt-caching.md`](./prompt-caching.md) | verify via `usage.cache_read_input_tokens` |
| `context-windows.md` | ✅ [`context-management.md`](./context-management.md) | overflow handling |
| `compaction.md` | ✅ [`context-management.md`](./context-management.md) | primary long-run strategy |
| `context-editing.md` | ✅ [`context-management.md`](./context-management.md) | fine-grained pruning |
| `token-counting.md` | ✅ [`context-management.md`](./context-management.md) | route/cost planning |
| `mid-conversation-system-messages.md` | ✅ [`context-management.md`](./context-management.md) | operator channel |
| `mid-conversation-effort-example.md` | ✅ [`thinking-and-effort.md`](./thinking-and-effort.md) | mid-stream effort change |
| `files.md` (Files API) | ✅ [`files-and-media.md`](./files-and-media.md) | upload once, reference many |
| `vision.md` | ✅ [`files-and-media.md`](./files-and-media.md) | image content path |
| `pdf-support.md` | ✅ [`files-and-media.md`](./files-and-media.md) | PDF content path |
| `citations.md` | ✅ [`files-and-media.md`](./files-and-media.md) | caching × citations nuance |
| `search-results.md` | ✅ [`files-and-media.md`](./files-and-media.md) | RAG citations |
| `embeddings.md` | ✅ [`files-and-media.md`](./files-and-media.md) | embeddings → tier-1 local preferred |
| `skills-guide.md` (Skills in the API) | ✅ [`tools.md`](./tools.md) | API-side Agent Skills |
| `multilingual-support.md` | ✅ [`model-matrix.md`](./model-matrix.md) | capability note |
| `claude-platform-on-aws.md` | 🔲 TODO `#13` | platforms.md (AWS deltas) |
| `claude-in-amazon-bedrock.md` | 🔲 TODO `#13` | platforms.md (Bedrock cache minimums differ) |
| `claude-on-amazon-bedrock-legacy.md` | 🚫 N/A | legacy path; WAVE never adopts |
| `claude-on-vertex-ai.md` | 🔲 TODO `#13` | platforms.md (Vertex deltas) |
| `claude-in-microsoft-foundry.md` (beta) | 🔲 TODO `#13` | platforms.md (Foundry deltas) |

(`adaptive-thinking` + `extended-thinking` + `effort` collapse to one file; counted once each above.)

## agents-and-tools/

| Page | Status | Note |
|------|--------|------|
| `tool-use/overview.md` | ✅ [`tools.md`](./tools.md) | |
| `tool-use/how-tool-use-works.md` | ✅ [`tools.md`](./tools.md) | where-tools-run axis |
| `tool-use/define-tools.md` | ✅ [`tools.md`](./tools.md) | define + `tool_choice` |
| `tool-use/handle-tool-calls.md` | ✅ [`tools.md`](./tools.md) | manual loop |
| `tool-use/tool-runner.md` (SDK) | ✅ [`tools.md`](./tools.md) | tool-runner vs manual |
| `tool-use/parallel-tool-use.md` | ✅ [`tools.md`](./tools.md) | |
| `tool-use/fine-grained-tool-streaming.md` | ✅ [`tools.md`](./tools.md) | beta-gated |
| `tool-use/strict-tool-use.md` | ✅ [`tools.md`](./tools.md) | |
| `tool-use/programmatic-tool-calling.md` | ✅ [`tools.md`](./tools.md) | PTC |
| `tool-use/tool-search-tool.md` | ✅ [`tools.md`](./tools.md) | |
| `tool-use/advisor-tool.md` | ✅ [`tools.md`](./tools.md) | beta `advisor-tool-2026-03-01` |
| `tool-use/server-tools.md` | ✅ [`tools.md`](./tools.md) | server-side tools |
| `tool-use/code-execution-tool.md` | ✅ [`tools.md`](./tools.md) | server tool |
| `tool-use/web-search-tool.md` | ✅ [`tools.md`](./tools.md) | server tool |
| `tool-use/web-fetch-tool.md` | ✅ [`tools.md`](./tools.md) | server tool |
| `tool-use/bash-tool.md` | ✅ [`tools.md`](./tools.md) | client tool (must sandbox) |
| `tool-use/text-editor-tool.md` | ✅ [`tools.md`](./tools.md) | client tool |
| `tool-use/computer-use-tool.md` | ✅ [`tools.md`](./tools.md) | client tool |
| `tool-use/memory-tool.md` | ✅ [`tools.md`](./tools.md) | client tool |
| `tool-use/tool-reference.md` | ✅ [`tools.md`](./tools.md) | schema reference |
| `tool-use/tool-combinations.md` | ✅ [`tools.md`](./tools.md) | canonical patterns |
| `tool-use/tool-use-with-prompt-caching.md` | ✅ [`tools.md`](./tools.md) + [`prompt-caching.md`](./prompt-caching.md) | cache tool defs |
| `tool-use/manage-tool-context.md` | ✅ [`tools.md`](./tools.md) + [`context-management.md`](./context-management.md) | |
| `tool-use/troubleshooting-tool-use.md` | ✅ [`tools.md`](./tools.md) | |
| `tool-use/build-a-tool-using-agent.md` (tutorial) | 🚫 N/A | tutorial; not a standard surface |
| `agent-skills/overview.md` | ✅ [`tools.md`](./tools.md) | Agent Skills via API |
| `agent-skills/quickstart.md` | 🚫 N/A | quickstart; not a standard surface |
| `agent-skills/best-practices.md` | ✅ [`tools.md`](./tools.md) | authoring guidance referenced |
| `agent-skills/enterprise.md` | 🚫 N/A | console/enterprise feature, not API spoke |
| `mcp-connector.md` | 🚫 N/A | WAVE MCP traffic routes through `mcp__wave__*` / gateway, not Anthropic's connector |
| `remote-mcp-servers.md` | 🚫 N/A | same — we host our own MCP, don't consume Anthropic's |
| `mcp-tunnels/overview.md` | 🚫 N/A | Anthropic-hosted tunnel product; WAVE uses CF tunnels |
| `mcp-tunnels/quickstart.md` | 🚫 N/A | same |
| `mcp-tunnels/console.md` | 🚫 N/A | same |
| `mcp-tunnels/reference.md` | 🚫 N/A | same |
| `mcp-tunnels/security.md` | 🚫 N/A | same |
| `mcp-tunnels/deploy-compose.md` | 🚫 N/A | same |
| `mcp-tunnels/deploy-helm.md` | 🚫 N/A | same |
| `mcp-tunnels/troubleshooting.md` | 🚫 N/A | same |

## managed-agents/

Entire section is the **Managed Agents** product (cloud sandboxes, sessions, vaults, dreams,
multi-agent, webhooks). WAVE runs its own agent chassis (dispatch + Leveragizer + Studio); we
do not consume Anthropic-managed agents today. Tracked as a single decision under task `#24`
(reconcile with Model Centralization + sovereign-local). All 22 pages are 🔲 TODO `#24` pending
that decision, except the product overview which is 🚫 N/A as a non-API marketing surface.

| Page | Status |
|------|--------|
| `overview.md` | 🚫 N/A (product overview, not an API we adopt) |
| `quickstart.md`, `onboarding.md`, `agent-setup.md`, `define-outcomes.md` | 🔲 TODO `#24` |
| `sessions.md`, `events-and-streaming.md`, `multi-agent.md`, `dreams.md` | 🔲 TODO `#24` |
| `environments.md`, `cloud-sandboxes-reference.md`, `self-hosted-sandboxes.md`, `self-hosted-sandboxes-security.md` | 🔲 TODO `#24` |
| `tools.md`, `skills.md`, `mcp-connector.md`, `memory.md` | 🔲 TODO `#24` |
| `files.md`, `vaults.md`, `github.md`, `permission-policies.md`, `webhooks.md` | 🔲 TODO `#24` |

(21 TODO + 1 N/A = 22.)

## manage-claude/

| Page | Status | Note |
|------|--------|------|
| `admin-api.md` | 🔲 TODO `#11` | admin-api.md (org/key/workspace mgmt) |
| `workspaces.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | workspace-per-tenant for USERS |
| `authentication.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | key/WIF auth |
| `workload-identity-federation.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | per-user WIF exchange |
| `wif-reference.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | WIF reference |
| `wif-providers/{aws,gcp,azure,github-actions,kubernetes,okta,spiffe}.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | provider matrix (7 pages; we use GH-Actions + GCP) |
| `usage-cost-api.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | attribution → Leveragizer budgets (task `#20`) |
| `rate-limits-api.md` | ✅ [`identity-and-usage.md`](./identity-and-usage.md) | programmatic limits |
| `api-and-data-retention.md` | ✅ [`context-management.md`](./context-management.md) + [`batch.md`](./batch.md) | ZDR posture; batch NOT ZDR; caching IS ZDR |
| `data-residency.md` | 🚫 N/A | gateway fixes residency region |
| `claude-code-analytics-api.md` | 🚫 N/A | Claude Code seat analytics, not a spoke API |
| `compliance-api.md` (overview) | 🚫 N/A | enterprise compliance export; not a spoke concern |
| `compliance-api-access.md` | 🚫 N/A | same |
| `compliance-integration-patterns.md` | 🚫 N/A | same |
| `compliance-org-data.md` | 🚫 N/A | same |
| `compliance-content-data.md` | 🚫 N/A | same |
| `compliance-activity-feed.md` | 🚫 N/A | same |
| `compliance-errors.md` | 🚫 N/A | same |
| `compliance-faq.md` | 🚫 N/A | same |

(The 7 `wif-providers/*` pages collapse to one ✅ row but are counted as 7 in the totals.)

## WAVE posture (load-bearing constants)

These are reconfirmed against the snapshot, not training data — where they disagree, the snapshot wins:

- Default model `claude-opus-4-8` (exact alias; never date-suffix). `sonnet-4-6` balanced; `haiku-4-5` fast.
- Opus 4.8/4.7: thinking **adaptive-only** (`budget_tokens`→400); `temperature`/`top_p`/`top_k`→400. Effort in `output_config.effort` (low|medium|high|max, +xhigh); default high; xhigh/max Opus-only; effort **ERRORS on haiku-4-5**. `thinking.display` omitted|summarized.
- Last-assistant prefill → 400 on opus-4.8/4.7/4.6 + sonnet-4.6; use `output_config.format` (`output_format` deprecated).
- Caching: prefix-match; `cache_control` ephemeral; top-level auto-cache; ≤4 breakpoints. Min cacheable prefix — live doc authoritative: **opus-4-8 = 1024** (older cached table said 4096 — nuance flagged), sonnet-4-6 = 1024, **haiku-4-5 = 4096**, opus-4.7/4.6/4.5 = 4096. read 0.1x / 5m write 1.25x / 1h write 2x. Verify via `usage.cache_read_input_tokens`.
- Stream when `max_tokens` > 16000. Batch API = 50% off, **NOT ZDR-eligible**. Prompt caching **IS** ZDR-eligible.
- Route via the model-routing Leveragizer (local→gateway→openrouter→direct→human); never bypass the gateway for direct Anthropic; never hardcode a model in code.

## Anti-patterns

- ❌ Treating per-language SDK reference pages as distinct surface — they are one endpoint; only Python+TS are sanctioned.
- ❌ Marking a page ✅ without the WAVE posture on it (caching/routing/never-hardcode). Coverage = posture, not paraphrase.
- ❌ Trusting the cached pricing table's 4096 min-prefix for opus-4-8 — the live `prompt-caching.md` says 1024.
- ❌ Adopting Managed Agents / MCP-tunnels surface silently — both are explicit 🚫/TODO decisions, not defaults.
- ❌ Re-running coverage against a stale `llms.txt` — always re-pull (see below) before diffing.

## Env vars

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_DOCS_INDEX_URL` | override the `llms.txt` URL for [Regenerate](#regenerate) (default `https://platform.claude.com/docs/en/llms.txt`) |
| `CLAUDE_DOCS_SNAPSHOT` | local snapshot root to diff against (default `/tmp/claude-docs-snapshot`) |

## Regenerate

Re-run this proof against a future index to surface drift. The recipe is curl + grep only:

```bash
# 1. Pull the live index
INDEX_URL="${ANTHROPIC_DOCS_INDEX_URL:-https://platform.claude.com/docs/en/llms.txt}"
curl -fsSL "$INDEX_URL" -o /tmp/claude-llms.new.txt

# 2. Extract canonical concept/endpoint pages, dropping per-language SDK variants
#    (lines tagged (cli)/(csharp)/(Go)/(Java)/(php)/(Python)/(Ruby)/(terraform)/(TypeScript))
grep -oE 'https://[^)]+\.md' /tmp/claude-llms.new.txt \
  | grep -vE '/(cli|csharp|go|java|php|python|ruby|terraform|typescript)/' \
  | sed -E 's#.*/docs/en/##' \
  | sort -u > /tmp/claude-pages.new.txt

# 3. Diff against the pages this COVERAGE.md enumerates
grep -oE '`[a-z0-9./_-]+\.md`' frameworks/claude-api/COVERAGE.md \
  | tr -d '`' | sort -u > /tmp/claude-pages.covered.txt

echo "=== NEW pages not yet in COVERAGE (add a row) ==="
comm -23 /tmp/claude-pages.new.txt /tmp/claude-pages.covered.txt

echo "=== pages we list that VANISHED from the index (remove/verify) ==="
comm -13 /tmp/claude-pages.new.txt /tmp/claude-pages.covered.txt
```

Any line under "NEW pages" is an uncovered surface: add a row marked ✅/🚫/🔲. Any line under
"VANISHED" is a deprecated page; confirm against the snapshot before deleting its row.
Re-snapshot the full bodies with `wget -r` or the existing scrape (task `#3`) when posture-bearing
facts must be re-verified — the grep diff catches new pages, not changed prose.

Sources: snapshot index `/tmp/claude-llms.txt`; snapshot pages `build-with-claude/prompt-caching.md` (min-prefix table L643-648: opus-4-8/`NextOpus`=1024, opus-4.7/4.6/4.5=4096, haiku-4.5=4096; multipliers L260-278; ttl L531-534), `build-with-claude/effort.md` (effort levels + model support L11-38), `build-with-claude/streaming.md`, `build-with-claude/batch-processing.md` (50% L83/L2207; NOT-ZDR L15), `api/{messages,models,admin,messages/batches}/*`, `manage-claude/{workload-identity-federation,wif-reference,wif-providers/*,usage-cost-api,api-and-data-retention,admin-api}.md`, `agents-and-tools/{tool-use,agent-skills,mcp-tunnels}/*`, `managed-agents/*`; companion files in this dir (headers cross-checked).
