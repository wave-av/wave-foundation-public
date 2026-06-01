# Audience Taxonomy

Who is a given file/section written for. Drives where content lives and how tools load it.

## Reader audiences

| Audience | Entry point | Notes |
|----------|-------------|-------|
| **Human** | `README.md`, `docs/` | Why/what, onboarding, quick-start |
| **Agent** | `AGENTS.md` (cross-tool), `CLAUDE.md` (Claude), `GEMINI.md` (Gemini), `rules/` | How to work; loaded by the tool |
| **User (end-user)** | product docs | The product's own users — out of foundation scope |

Mixed sections use HTML-comment tags so the wrong audience can skip:
`<!-- human-only: ... -->` and `<!-- agent-only: ... -->`.

## Instruction-type trichotomy (for agents)

| Type | Purpose | When loaded |
|------|---------|-------------|
| **Rules** | Enforcement — MUST / NEVER | When editing matching files |
| **Skills** | Capability — "the agent CAN do X" | At startup (descriptions) |
| **Memories** | Reference — "HOW to do X" | On `@`-import / on demand |

## Actor priority (who may write where)

When multiple actors touch one repo (human, agent, bots), highest priority wins the working
branch: **Human/interactive > automated pipeline > bot-fix branch > Dependabot/Renovate >
auto-commit.** Bots use their own `fix/*` branches; never direct-push to protected branches.

## Public vs private

Agent instructions split into **public-safe** (committed `AGENTS.md`) and **private overlay**
(`AGENTS.local.md`, gitignored — overrides, never holds secrets/business rules). See
[`OPEN-CORE.md`](../OPEN-CORE.md) for which paths are public-extractable.
