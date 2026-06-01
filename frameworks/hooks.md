# Hooks Pack

The standard hook pipeline, proven across wave-surfer-connect + claude-hub. Install via the foundation plugin (once `plugin/` exists) or copy the reference implementations from `~/.claude/hooks/` and `wave-surfer-connect/.claude/hooks/`.

## Global hooks (~/.claude/hooks/ — applies to all projects)

| Hook | Event | Purpose |
|------|-------|---------|
| `circuit-breaker.sh` | PreToolUse(Bash) | Blocks known dangerous shell patterns |
| `file-size-warning.sh` | PreToolUse(Read) | Warns when reading files over soft limit |
| `supabase-prod-guard.py` | PreToolUse(mcp__*supabase*__apply_migration\|execute_sql) | **BLOCKS** direct prod writes — exits 2 if project_id is in `WAVE_SUPABASE_PROD_REFS` (env-configured; private overlay) |
| `mcp-chunker.sh` | PostToolUse(mcp__*) | Chunks large MCP results to prevent context blow-up |
| `post-write-format.sh` | PostToolUse(Write\|Edit) | Runs formatter after file writes |
| `failure-handler.sh` | PostToolUseFailure | Logs tool failures for debugging |
| `post-compact-restore.sh` | PostCompact | Restores key context after compaction |

### Local LLM hooks (Ollama — require Mac Studio or local Ollama)

| Hook | Event | Purpose |
|------|-------|---------|
| `local-llm/session-warmup.sh` | SessionStart(async) | Pre-warms Ollama model |
| `local-llm/task-router.sh` | UserPromptSubmit | Classifies task, injects routing hint |
| `local-llm/prompt-enhancer.sh` | UserPromptSubmit | Structures/cleans prompt via local LLM |
| `local-llm/context-compressor.sh` | PostToolUse(async) | Summarizes verbose tool output |
| `local-llm/code-reviewer.sh` | PostToolUse(Write\|Edit)(async) | Local code review on every write |

Kill switch: `touch /tmp/claude/ollama-disabled` to disable all local LLM hooks.

## Project hooks (wave-surfer-connect — proven patterns for complex projects)

### Guards (PreToolUse — can exit 2 to block)

| Hook | Blocks |
|------|--------|
| `automation/guard-secret-scan.sh` | Commits containing secret patterns (`sk-`, `ghp_`, `AKIA`, etc.) |
| `automation/guard-rls-migration.sh` | Migrations without `ENABLE ROW LEVEL SECURITY` |
| `automation/guard-owasp-scan.sh` | Code patterns matching OWASP Top 10 |
| `agent-routing-guard.sh` | Spawns of forbidden agent types (Explore, general-purpose) |

### Intelligence hooks (PostToolUse/Stop — async, non-blocking)

| Hook | Purpose |
|------|---------|
| `automation/intelligence-session-learnings.sh` | Captures session learnings to memory |
| `automation/intelligence-retrospective.sh` | End-of-session retrospective |
| `automation/intelligence-task-quality.sh` | Scores task quality for learning |
| `automation/intelligence-subagent-metrics.sh` | Tracks agent spawn efficiency |
| `automation/intelligence-knowledge-curation.sh` | Curates knowledge base entries |

### Lifecycle hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `automation/lifecycle-init.sh` | SessionStart | Warm session state, load context |
| `automation/lifecycle-cleanup.sh` | Stop | Clean temp files, finalize session |
| `automation/lifecycle-prompt-preprocess.sh` | UserPromptSubmit | Pre-process prompts |

### Automation triggers (Stop — spawn background agents)

| Hook | Trigger condition | Spawns |
|------|-------------------|--------|
| `automation/trigger-babysit-prs.sh` | After PR create | PR monitoring agent |
| `automation/trigger-ci-fixer.sh` | After push | CI failure fixer agent |
| `automation/trigger-deploy-health.sh` | After deploy | Health check agent |

## Git-stage gates (shift CI left to commit/PR time)

CI checks that only fire **after** a push or PR is opened are waste — you discover the red X after the
fact. The pattern: take a CI rule, give it ONE source-of-truth script, and call that same script from a
local git-stage hook so the failure is caught as the work is created. CI keeps the script as a parity
step so the two can never drift.

| Script | Local stage | Mirrors (CI) | Catches |
|--------|-------------|--------------|---------|
| `hooks/validate-conventional-title.sh` | `commit-msg` (pre-commit) | `.github/workflows/semantic-pr.yml` | Bad commit/PR titles (non-conventional type, uppercase subject) before they reach CI |
| `hooks/pr-title-preflight.sh` | manual, before `gh pr create` | same | A bad `--title` before the PR exists (`--create` validates then creates) |

Wiring (foundation dogfoods both):
- `.pre-commit-config.yaml` registers `conventional-title` at `stages: [commit-msg]` and sets
  `default_install_hook_types: [pre-commit, commit-msg]` so `pre-commit install` wires the git hook.
- `semantic-pr.yml` runs the **same** `validate-conventional-title.sh` against the PR title as a parity
  step — if the script and the amannn action ever disagree, the rule drifted; fix the script.
- Spokes inherit it via `consume.sh` (vendored to `.foundation/frameworks/hooks/`). To enable in a spoke,
  add a `repo: local` `commit-msg` hook pointing at `.foundation/frameworks/hooks/validate-conventional-title.sh`.

One rule, three call sites (commit-msg hook · PR-create preflight · CI parity) — a title can't fail in CI
without first failing locally. This is the seed of a broader **left-shift gate** family: version-sync,
file-size, foundation-pin drift, and verify-routes all have the same shape — a CI rule that should also
run at commit/push time off a shared script.

## Hook standards

- Always `set +e` — hooks must not crash Claude
- Timeout: `PreToolUse` ≤ 10s, `PostToolUse` async ≤ 30s
- Exit 2 to **block** the tool call (PreToolUse only)
- Exit 0 for pass-through (all other cases)
- Output to stderr, not stdout (stdout is parsed by Claude)
- Kill switch pattern: `[ -f /tmp/claude/hook-disabled ] && exit 0`

## Dogfood law

Every hook here must be one that's actually running in at least one project. Aspirational hooks are drafts, not framework.
