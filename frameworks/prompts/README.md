# Prompt-context hooks (reference)

Cross-project Claude Code hooks that **enrich the prompt with context** at well-defined lifecycle
points, so the model sees the right project state without manual setup. Promoted from the WSC
harvest (0 WAVE refs — all generic).

| Hook | Event | Purpose |
|---|---|---|
| `session-start-context.sh` | SessionStart | Loads project context (rules, recent activity, environment) so the session opens with the right priors instead of cold |
| `lifecycle-prompt-preprocess.sh` | UserPromptSubmit | Preprocesses the prompt — normalizes, attaches lifecycle metadata, routes by intent |
| `graph-prompt-context.sh` | UserPromptSubmit | Attaches code-graph blast-radius / dependency context when the prompt references symbols (pairs with `code-review-graph` MCP if installed) |

## How to use

These are **reference patterns** — adapt to your project. Wire them into your
`.claude/settings.json` (or the plugin's `hooks.json`) under the matching event. They degrade
cleanly (no-op) when dependencies (MCP servers, tools) aren't present.

## Why they matter

Without context-injection hooks, every prompt starts cold and forces re-discovery of facts that are
already known. With them: rules + recent activity + relevant code surface flow in automatically.
This is the "**safe context injection**" pattern — additive, predictable, gate-able.

## Follow-up promotions

Two more high-value hooks need shellcheck cleanup (SC2155 `local x=$(cmd)` splits) before they can
be promoted to canonical:

- `staging/_external/wsc-claude/hooks/agent-context-injector.sh` (agent-routing context)
- `staging/_external/wsc-claude/hooks/lib/additional-context-lib.sh` (the shared library)

Once cleaned, they slot in here too. The harvest tier (`staging/_external/wsc-claude/hooks/`) holds
many more lifecycle/prompt hooks (prompt-enhancer, mcp-enable-prompt, graph-context-enricher,
session-start-context-loader, …) — promote on demand per `docs/promotion.md`.
