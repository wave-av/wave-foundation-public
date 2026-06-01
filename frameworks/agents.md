# WAVE Agent System AGENTS.md

> Central registry for 177 specialist agents with Claude Code integration.

---

## Agent Taxonomy (177 Specialists)

### By Domain

| Domain           | Count | Key Agents                                                                                                    |
| ---------------- | ----- | ------------------------------------------------------------------------------------------------------------- |
| Streaming/Media  | 12    | `video-quality-optimizer`, `stream-analytics-specialist`, `streaming-protocols-specialist`                    |
| Payments/Billing | 8     | `stripe-payments-specialist`, `billing-reconciliation-specialist`, `subscription-lifecycle-specialist`        |
| Security         | 7     | `security-code-review-specialist`, `threat-intelligence-analyst`, `gdpr-compliance-specialist`                |
| AI/ML            | 15    | `ai-cost-prediction-optimizer`, `model-routing-specialist`, `anthropic-claude-integration-specialist`         |
| Database         | 7     | `supabase-database-specialist`, `schema-evolution-automation-specialist`, `database-schema-memory-specialist` |
| DevOps           | 15    | `deployment-devops-specialist`, `ci-cd-resolution-specialist`, `vercel-deployment-specialist`                 |
| Testing          | 5     | `testing-qa-specialist`, `test-coverage-review-specialist`, `autonoma-testing-specialist`                     |
| Frontend         | 8     | `frontend-ux-specialist`, `design-system-specialist`, `accessibility-compliance-specialist`                   |
| Observability    | 10    | `monitoring-observability-specialist`, `sentry-specialist`, `dash0-specialist`                                |
| Communication    | 6     | `slack-automation-specialist`, `email-delivery-automation-specialist`, `notification-dispatcher`              |

### By Tool Access Needs (MCP Servers)

| MCP Server | Agents    | Use When                                  |
| ---------- | --------- | ----------------------------------------- |
| supabase   | 12 agents | Database queries, migrations, RLS         |
| stripe     | 6 agents  | Payments, subscriptions, billing          |
| sentry     | 5 agents  | Error tracking, debugging                 |
| github     | 8 agents  | PRs, workflows, code review               |
| linear     | 4 agents  | Issue tracking, TaskCreate/TodoWrite sync |
| cloudflare | 6 agents  | Streaming, CDN, Workers                   |
| dash0      | 4 agents  | Metrics, OTEL, observability              |

---

## Spawner Integration

### Smart Mode (Recommended)

```bash
bash .claude/scripts/mcp-agent-spawn.sh --mode smart --task "Your task"
```

### Efficiency Modes (66 Available)

| Mode                | Savings | Use Case              |
| ------------------- | ------- | --------------------- |
| `smart`             | 90-99%  | Auto-detect best mode |
| `pattern`           | 98%     | Bulk find-replace     |
| `micro`             | 95%     | Single operations     |
| `pr-review`         | 90%     | GitHub PR analysis    |
| `verification-flow` | 90%     | Multi-step checks     |

### Context Budget Rules

- **Single objective per spawn** (context <30% optimal)
- **Maximum 60%** for complex bug fixes
- **Above 90%**: Use `/clear` first

### A/B Testing for Optimization Agents

**CRITICAL: All optimization work MUST be A/B tested.**

When agents work on efficiency, performance, or context optimization:

1. **Preserve original** before any changes
2. **Create new version** alongside original
3. **Measure both** with identical conditions
4. **Document comparison** at `.claude/docs/ab-tests/`
5. **Decide on data** - not assumptions

Applies to: `context-compression-specialist`, `performance-optimization-specialist`, `thinking-budget-manager`, and any agent claiming to "improve" something.

See: `.claude/rules/00-core/ab-test-optimizations.md`, `.agents/optimization.md`

---

## Agent Frontmatter Standard

```yaml
---
name: streaming-protocols-specialist
description: WebRTC, SRT, RTMP protocol expert
version: 1.0.0
agents_md:
  primary: src/services/streaming/AGENTS.md
  secondary:
    - src/services/billing/AGENTS.md
    - .agents/performance.md
collaboration:
  handoff_to:
    - billing-reconciliation-specialist
  receives_from:
    - broadcast-production-specialist
mcp_servers:
  - cloudflare
  - mux
  - livekit
---
```

See: `.claude/docs/AGENT-FRONTMATTER-GUIDE.md`

---

## Commands

| Task         | Command                                                                            |
| ------------ | ---------------------------------------------------------------------------------- |
| Smart spawn  | `bash .claude/scripts/mcp-agent-spawn.sh --mode smart --task "..."`                |
| With servers | `bash .claude/scripts/mcp-agent-spawn.sh --servers supabase,stripe --task "..."`   |
| PR review    | `bash .claude/scripts/mcp-agent-spawn.sh --mode pr-review --task "Review PR #123"` |
| Agent chain  | `bash .claude/scripts/mcp-agent-chain.sh --step "..." --step "..."`                |

---

## Agent Discovery

```bash
# Find agents for a task
grep -r "streaming" .claude/agents/*.md --files-with-matches

# List all agents
ls -la .claude/agents/*.md | wc -l

# Agent capabilities
head -50 .claude/agents/<agent-name>.md
```

---

## Cross-Functional Agent Flows

### Stream Creation Flow

```
broadcast-production-specialist
  → streaming-protocols-specialist
  → billing-reconciliation-specialist
  → notification-dispatcher
```

### Error Resolution Flow

```
sentry-specialist
  → code-reviewer
  → testing-qa-specialist
  → github-pr-automation
```

### Payment Processing Flow

```
stripe-payments-specialist
  → subscription-lifecycle-specialist
  → email-delivery-automation-specialist
  → linear-task-automation
```

---

## Boundaries

- **Always**: Use spawner script, single objective tasks
- **Ask first**: Multi-agent parallel execution
- **Never**: Direct Task tool calls (use spawner), multi-objective spawns

## MCP Servers

| Operation      | Server     | Key Tools                                        |
| -------------- | ---------- | ------------------------------------------------ |
| Agent Database | `supabase` | `execute_sql` (agent state, spawn history)       |
| Agent Errors   | `sentry`   | `search_issues` (agent failures)                 |
| Task Sync      | `linear`   | `create_issue` (TaskCreate + TodoWrite → Linear) |
| Metrics        | `dash0`    | `PromQL` (agent performance)                     |

**Quick enable:** `bash .claude/scripts/mcp-agent-spawn.sh --servers supabase,sentry,linear,dash0 --task "..."`

---

## Learning Log

### 2026-01-28: Agent Spawned Without Mode Selection

❌ Agent spawned with direct Task tool call, missing efficiency mode optimization
✅ ALWAYS use spawner: `bash .claude/scripts/mcp-agent-spawn.sh --mode smart --task "..."`
**Rule:** Never call Task tool directly - spawner provides 70-98% token savings

---

_v1.1.0 | Updated: 2026-01-29 | Owner: @platform-team | Stale after: 30 days_
