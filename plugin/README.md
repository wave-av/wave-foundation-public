# wave-foundation Plugin

Installable Claude Code plugin that ships WAVE's guard hooks and plan skills as a single unit.

## Install

```bash
# From the wave-foundation repo root:
claude plugin install ./plugin
```

Or once published:

```bash
claude plugin install wave-av/wave-foundation
```

## What Ships

### Hooks (auto-wired on install)

| Hook | Event | Purpose |
|------|-------|---------|
| `supabase-prod-guard.py` | PreToolUse | Blocks direct writes to any Supabase project listed in `WAVE_SUPABASE_PROD_REFS` (comma-separated env var; configure per environment). Exits 2 to hard-block. |
| `file-size-warning.sh` | PreToolUse (Write/Edit) | Warns at 500 lines, blocks at 800. |
| `post-write-validator.sh` | PostToolUse (Write/Edit) | Checks for mock data, hardcoded colors, @ts-ignore patterns. |
| `circuit-breaker.sh` | PreToolUse (Bash) | Blocks dangerous commands (`rm -rf /`, `chmod 777`, etc.) on the primary command only. |
| `session-start.sh` | SessionStart | Prints rule summary, warns if prod guard not wired. |
| `skill-frontmatter-guard.sh` | PostToolUse (Write/Edit) | Validates a `SKILL.md`'s frontmatter the moment it's written — catches a bad edit in-session, not days later in CI. |

### Skills (invoked as `/skill-name`)

| Skill | Purpose |
|-------|---------|
| `/plan-generate` | Transform context/ideas into a structured plan |
| `/plan-enhance` | Deep research + gap analysis to strengthen a plan |
| `/plan-to-action` | Decompose a plan into 50-500 atomic TaskCreate tasks with dependencies |
| `/plan-audit` | Post-implementation audit — 7 modes (smoke → comprehensive) |
| `/wave-execute` | Execute tasks wave-by-wave with milestone gates (tsc + lint) |

## What Does NOT Ship (keep in source repos)

- Project-specific CLAUDE.md rules
- MCP server configurations (`.mcp.json`)
- Product-specific tokens (design-system files)
- Agent definitions (AGENTS.md)

## Discovery Convention (added 2026-05-29 — PR N)

`plugin.json`'s `hooks` and `skills` arrays are intentionally empty. Claude Code's plugin loader auto-discovers components via convention:

- **Hooks**: `plugin/hooks/hooks.json` is the source of truth. Each entry maps an event matcher (`PreToolUse`, `PostToolUse`, `Stop`, `SessionStart`, etc.) to a command that runs at that lifecycle point. Adding a new hook = a row in `hooks.json` + the executable script next to it.
- **Skills**: every `plugin/skills/<name>/SKILL.md` is auto-registered as `/<name>`. Adding a new skill = creating a new directory with a valid SKILL.md (frontmatter validates via the in-session `skill-frontmatter-guard.sh` hook + the `validate-skills.py` CI gate).

Why not declare them in `plugin.json`? Three reasons:

1. The discovery files (`hooks.json` + SKILL.md frontmatter) carry the wiring details (matchers, timeouts, allowed-tools) that `plugin.json` can't express
2. Adding a hook or skill needs to touch only ONE file (the convention) instead of two
3. `plugin_install_smoke` dogfood gate verifies the discovery output, so the loader's behavior is asserted regardless of whether `plugin.json` redundantly lists components

The `plugin_install_smoke` dogfood gate (`scripts/plugin-install-smoke.sh`) walks `hooks.json` + every `SKILL.md` to verify every discovered component resolves, is executable, and is sandbox-bounded.

## Directory Structure

```
plugin/
  .claude-plugin/
    plugin.json          ← manifest
  hooks/
    hooks.json           ← event → script wiring
    supabase-prod-guard.py
    file-size-warning.sh
    post-write-validator.sh
    circuit-breaker.sh
    session-start.sh
    skill-frontmatter-guard.sh
  skills/
    plan-generate/SKILL.md
    plan-enhance/SKILL.md
    plan-to-action/SKILL.md
    plan-audit/SKILL.md
    wave-execute/SKILL.md
```

## Version Pinning

Pin the foundation commit in each project's README or `.foundation-version`:

```bash
echo "$(git -C ~/wave-foundation rev-parse HEAD)" > .foundation-version
```

CI can verify the pin matches: `git -C ~/wave-foundation rev-parse HEAD`.
