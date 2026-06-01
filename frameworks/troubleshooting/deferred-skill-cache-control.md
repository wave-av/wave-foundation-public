# Deferred Skill cache_control Empty Text Block Error

## Problem

When running `/mcp:<server>` skills (e.g., `/mcp:linear`), Claude Code throws:

```
API Error: 400 {"type":"error","error":{"type":"invalid_request_error",
"message":"messages.X.content.Y.text: cache_control cannot be set for empty text blocks"}}
```

## Root Cause

1. WAVE MCP skills are intentionally **deferred** (lazy-loaded)
2. Skill files contain only frontmatter, no content body:

   ```markdown
   ---
   name: linear
   description: "Linear project management MCP operations"
   category: mcp
   deferred: true
   ---
   ```

3. The actual MCP tools load **after** the skill enables the server
4. **Bug in Claude Code SDK**: The Skill tool sets `cache_control` on the empty content block
5. Anthropic API rejects `cache_control` on empty text blocks

## NOT a WAVE Bug

This is a Claude Code SDK bug, not a WAVE configuration issue. The deferred pattern is intentional for lazy-loading MCP servers.

## Workaround

**Use `mcp-agent-spawn` instead of the Skill tool:**

```bash
# Instead of: /mcp:linear
# Use:
bash .claude/scripts/mcp-agent-spawn.sh --servers linear --task "List recent issues"
```

Or spawn the specialized agent directly:

```bash
Task(subagent_type="linear-task-automation", prompt="List recent Linear issues")
```

## Files Affected

All deferred MCP skills in `.claude/commands/mcp/`:

- `linear.md`
- `supabase.md`
- `sentry.md`
- `stripe.md`
- `dash0.md`
- `github.md`
- `cloudflare.md`

## Potential Fix (Claude Code Team)

The Skill tool should check for empty content before setting `cache_control`:

```typescript
// Before setting cache_control, check content is not empty
if (content && content.trim().length > 0) {
  block.cache_control = { type: "ephemeral" };
}
```

## Related

- Commit `e71dba9a8c` - WAVE-side fix for `src/lib/anthropic.ts` (different code path)
- `.claude/commands/mcp/` - MCP skill definitions
- `.claude/scripts/mcp-agent-spawn.sh` - Workaround spawner

---

_Documented: 2026-01-25_
