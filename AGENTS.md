# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

This is Jake's command center for Codex. A git-tracked home base for configuration, navigation, and cross-project coordination.

## Environment

- **Machine:** macOS (Darwin), zsh shell
- **Model:** Opus 4.6 with 1M context, always-thinking enabled
- **Hooks:** Circuit breaker (Bash), file chunking (Read), MCP chunking (PostToolUse), failure handler (PostToolUseFailure)
- **MCP profiles:** Managed configs in `~/.Codex/mcp-configs-managed/` (ai, full, minimal, monitoring, payment, streaming)

## Projects

| Directory | What it is |
|-----------|-----------|
| `~/burnrate/` | Main project. macOS Electron menubar app tracking Codex subscription usage. Has its own AGENTS.md. |
| `~/Codex-protocol-suite/` | Custom skills for Codex |
| `~/dev/test-app/` | Test/scratch app |
| `~/WAVE-Inc/wave-surfer-connect/` | WAVE: cloud broadcast platform (Next.js, Supabase, Cloudflare, 74 agents) |
| `~/WAVE-Inc/` | WAVE work projects parent directory |

When asked to work on something, figure out which project it belongs to and operate from that directory. For BurnRate work, read `~/burnrate/AGENTS.md` first — it has critical rules (OKLCH-only colors, IPC surface, etc.).

## Workflow Preferences

- **Plan-to-Action Protocol:** After any plan is accepted, ALWAYS create an atomic task breakdown (one task per logical change per file) with dependency mapping BEFORE writing code. Present the task table and wait for acknowledgment.
- **Memory system:** Persistent memory in `~/.Codex/projects/` (per-project). Check `.Codex/memories/INDEX.md` for tiered index.
- When unsure which project the user means, ask — don't guess.

## File Size & Line Count Rules

Keep files short. Lower line counts = faster processing through context gates. Split files for efficiency rather than growing them.

**Target ranges by file type:**

| Range | Typical file types |
|-------|--------------------|
| ~200 | Config, JSON, small scripts, shell utilities |
| ~400 | Component files, helpers, single-purpose modules |
| ~500-600 | Standard source files, services, controllers |
| ~700-800 | Larger modules, complex components (upper comfort zone) |
| 1000+ | Avoid — split if approaching this. Exceptions exist by file type. |

When creating or modifying files, default to the lower end. If a file is growing past its range, split it out before it becomes a problem.

## Code Standards (for this repo)

### Conventions

- All scripts read from `projects.json` (single source of truth)
- Use `python3 -c` for JSON parsing (not jq)
- Templates use `{{PLACEHOLDER}}` syntax with `# === CUSTOMIZE ===` markers
- Skills are self-contained in `.Codex/skills/<name>/SKILL.md`
- Rules use numbered directories: `00-core/`, `25-quality/`, `90-workflow/`

### Prohibited Patterns

- No hardcoded paths (`/Users/jakefineman/` — use `$HOME` or `~`)
- No secrets in tracked files
- No `set -e` in hooks (use `set +e` — predictable error handling)
- No files over 800 lines

## Validation gates (apply to every agent — Codex, Claude, humans)

This repo enforces the same checks regardless of who or what edits it:

- **Pre-commit (local, tool-agnostic):** `.pre-commit-config.yaml` runs on every `git commit` —
  validates YAML syntax and every `SKILL.md` frontmatter via `scripts/validate-skills.py`. A broken
  skill (empty `allowed-tools`, duplicate keys, `name` ≠ directory, missing description) **blocks the
  commit** — for any committer. Activate once: `pip install pre-commit && pre-commit install`.
- **CI**: `self-check.yml` (secret-scan + file-size + `skill-validate`) plus the reusable
  `checks.yml` dogfooded via `dogfood-gate.yml` — the same gate consumers inherit — on every PR/push.
- **Claude Code (bonus, in-session):** `plugin/hooks/skill-frontmatter-guard.sh` validates a `SKILL.md`
  the moment it's written. (Codex doesn't read this hook — the pre-commit gate covers it instead.)
- **Editor:** install `redhat.vscode-yaml`; `.vscode/settings.json` maps schemas for live YAML validation.

Before committing skills, run `python3 scripts/validate-skills.py` yourself.

## What Lives Here

### Root

- `AGENTS.md` — this file (cross-project guidance)
- `projects.json` — machine-readable project registry (paths, tags, MCP profiles)
- `statusline.sh` — shared statusline script for Codex
- `launch.sh` — quick-launch: cd + MCP profile switch + start Codex

### Scripts

- `scripts/lib/common.sh` — shared functions (load_projects, validate_registry)
- `scripts/sweep.sh` — git status across all registered projects
- `scripts/sync.sh` — pull all repos (supports `--dry-run`)
- `scripts/dashboard.sh` — unified snapshot (system, BurnRate, projects, MCP)
- `scripts/health-check.sh` — automated 19+ point validation

### Docs (customization reference, split by topic)

- `docs/customization-overview.md` — master index of all Codex extension points
- `docs/settings-reference.md` — all settings.json keys
- `docs/hooks-reference.md` — all hook events, matchers, I/O
- `docs/skills-agents.md` — creating custom skills and agents
- `docs/permissions.md` — permission modes and rule syntax
- `docs/mcp-profiles.md` — your 7 managed MCP configs
- `docs/hooks.md` — your active hooks catalog

### Skills (14 `/slash` commands)

- `/sweep` — cross-project git status
- `/dashboard` — unified snapshot
- `/sync` — pull all repos
- `/switch-profile` — change MCP config
- `/goto` — navigate to a project
- `/audit-config` — audit Codex setup across all projects
- `/new-project` — bootstrap Codex for a new project from templates
- `/status` — quick status (git, MCP, hooks, plugins)
- `/tasks` — cross-project task dashboard (branches, PRs, commits)
- `/analytics` — session analytics (hook logs, Ollama stats)
- `/ollama-setup` — manage Ollama models (create, test, status)
- `/methodology-audit` — run methodology engine against this project
- `/sync-config` — export/import Codex config across machines
- `/imessage-setup` — configure iMessage channel for mobile access

### Agents (3)

- `hub-manager` — manages hub config, registry, and scripts
- `config-auditor` — audits Codex setup for issues
- `template-builder` — extracts reusable patterns into templates

### Rules (numbered directories, 10 rules)

- `00-core/` — hub-conventions, no-hardcoded-paths, no-secrets, projects-json-source-of-truth
- `25-quality/` — file-size, template-standards, docs-accuracy, script-robustness
- `90-workflow/` — plan-before-code, update-on-change

### Memory (tiered)

- `.Codex/memories/INDEX.md` — Tier 1 (always loaded) + Tier 2 (on-demand)
- `.Codex/memories/wave-patterns.md` — patterns extracted from WAVE

### Infrastructure

- `.Codex/plans/` — working directory for feature-dev plugin plans
- `.Codex/methodology-cycles/` — cycle history for methodology engine
- `.git/hooks/pre-commit` — validates JSON, secrets, frontmatter before commits
- `methodology-registry.json` — 20 adapted methodologies with cycle tracking
- `scripts/methodology-cycle.sh` — record/history/next cycle commands
- `scripts/sync-config.sh` — export/import ~/.Codex/ config across machines
- `config-sync/` — exported config snapshot (hooks, agents, rules, settings)

## Local / Private Overrides

This file is **public-extractable** (see [`OPEN-CORE.md`](OPEN-CORE.md)). Machine- or org-private
guidance goes in **`AGENTS.local.md`** (gitignored), which **overrides** this file (nearest/last
wins). Codex also honors per-dir `AGENTS.override.md`; Claude honors `CLAUDE.local.md`. Never put
secrets or business rules in the committed `AGENTS.md`. See `AGENTS.local.md.example` for the shape.

## Audience

`README.md` is the **human** entry point; `AGENTS.md` (this file) + `CLAUDE.md` are the **agent**
entry points (Gemini/Cursor/Copilot/Grok read `AGENTS.md` — see `GEMINI.md`, `.cursor/rules/`,
`.github/copilot-instructions.md`). For mixed content, tag sections with `<!-- human-only -->` /
`<!-- agent-only -->`. Full audience model: [`taxonomy/audiences.md`](taxonomy/audiences.md).

### Templates (reusable patterns from wave-surfer-connect)

- `templates/hooks/` — 17 hook templates (circuit breaker, session lifecycle, permissions, tracking, devops, local-llm, automation)
- `templates/agents/` — 6 agent templates (backend, database, frontend, security, testing, PR review)
- `templates/skills/` — 2 skill templates (validate, golden-path scaffold)
- `templates/rules/` — 3 rule templates (no-mock-data, file-size, commit-quality)
- `templates/workflows/` — 2 workflow definitions (bug-fix, feature-implementation)
- `templates/configs/` — 3 config templates (settings, MCP governance, permissions)
- `templates/ollama/` — 6 Modelfiles (prompt-enhancer, classifier, drafter, reviewer, intent, methodology)
