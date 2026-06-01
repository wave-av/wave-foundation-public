# WAVE Troubleshooting Index

> Quick reference for common issues and their solutions

---

## Error Detection Hooks

| Hook                              | Detects                   | Solution File               |
| --------------------------------- | ------------------------- | --------------------------- |
| `github-secret-error-detector.sh` | GitHub secrets HTTP 400   | `github-secrets-http400.md` |
| `next-lock-error-detector.sh`     | Next.js build lock errors | `nextjs-build-lock.md`      |

---

## Common Issues

### GitHub & CI/CD

| Issue                         | Quick Fix                                                              | Docs                                                             |
| ----------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **GitHub Secrets HTTP 400**   | Use `--org` flag: `node scripts/set-github-secret.mjs KEY "val" --org` | [Details](github-secrets-http400.md)                             |
| **Actions Permission Denied** | Check `gh auth status` for required scopes                             | GitHub Docs |

### Build & Development

| Issue                 | Quick Fix                                         | Docs                                              |
| --------------------- | ------------------------------------------------- | ------------------------------------------------- |
| **Next.js Lock File** | `rm -f .next/lock && pkill -f "next"`             | [Details](nextjs-build-lock.md)                   |
| **TypeScript Errors** | `npm run type-check` then fix reported errors     | TS Guide |
| **Build OOM**         | `export NODE_OPTIONS="--max-old-space-size=8192"` | Memory Guide     |

### Claude Code / MCP

| Issue                                    | Quick Fix                                                                    | Docs                                                            |
| ---------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------- |
| **Plan Skill Empty Response**            | Skills now handle gracefully; use scripts directly if needed                 | [Details](plan-skill-empty-response.md)                         |
| **Deferred Skill cache_control Error**   | Use `mcp-agent-spawn` instead of `/mcp:*` skills                             | [Details](deferred-skill-cache-control.md)                      |
| **MCP Server Timeout**                   | Run `/mcp enable <server>` manually                                          | MCP Guide                     |
| **Gateway Context Error (2.1.27+)**      | Set `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`                               | [Gateway Fix](gateway-context-validation.md)                    |
| **PDF Read Fails (2.1.30+)**             | Use `pages` param for >10 page PDFs: `Read(path, pages: "1-20")`             | 2.1.30 Features |
| **MCP OAuth Token Expired (2.1.30+)**    | Check `.claude/state/oauth/` for refresh tokens                              | OAuth Guide             |
| **Task Metrics Missing (2.1.30+)**       | Verify `taskToolMetrics` feature flag enabled                                | 2.1.30 Features |
| **Subagent MCP Tools Missing (2.1.30+)** | Check subagent sync validator logs in `.claude/state/debug/tool-calls.jsonl` | 2.1.30 Features |

### Authentication

| Issue                  | Quick Fix                                | Docs                                          |
| ---------------------- | ---------------------------------------- | --------------------------------------------- |
| **Auth Redirect Loop** | Check `secure` cookie flag matches HTTPS | Auth Guide |
| **Session Expired**    | Clear cookies, re-authenticate           | Session Docs      |

### Database

| Issue                    | Quick Fix                                             | Docs                                                                |
| ------------------------ | ----------------------------------------------------- | ------------------------------------------------------------------- |
| **RLS Policy Violation** | Verify `organization_id` filter in query              | RLS Patterns |
| **Migration Failed**     | Check staging first: `mcp__supabase__list_migrations` | DB Guide                          |

### Optimization & Performance

| Issue                              | Quick Fix                                        | Docs                                                                  |
| ---------------------------------- | ------------------------------------------------ | --------------------------------------------------------------------- |
| **Optimization Made Things Worse** | Restore from `.v1` backup or git history         | [Details](optimization-regression.md)                                 |
| **No Baseline to Compare**         | Check git history, reconstruct, document failure | A/B Testing Rule |

---

## Adding New Issues

When you encounter and resolve a new issue:

1. **Create troubleshooting doc:**

   ```
   .claude/troubleshooting/<issue-name>.md
   ```

2. **Document the journey:**
   - Problem statement
   - Investigation timeline (what you tried)
   - Root cause
   - Solution
   - Detection patterns

3. **Create detection hook (optional):**

   ```
   .claude/hooks/<issue>-error-detector.sh
   ```

4. **Update this index**

---

## Hook Integration

Hooks are automatically triggered by Claude Code on PostToolUse events.

To register a new detection hook:

1. Create the hook in `.claude/hooks/`
2. Add to `.claude/settings.json` under `hooks.PostToolUse`
3. Hook receives tool output as $1

---

_Last Updated: 2026-02-03 (Claude Code 2.1.30 integration)_
