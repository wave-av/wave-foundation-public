# Plan Skill Empty Response Error

## Problem

The `/plan:validate` and `/plan:enhance` skills throw API errors:

```
API Error: 400 {"type":"error","error":{"type":"invalid_request_error",
"message":"messages: text content blocks must be non-empty"}}
```

## Root Cause

The .mdx command files run bash scripts that can return empty output when:

1. **No plans exist** in `.claude/plans/`
2. **plan-validate.sh** exits with error code but no output
3. **prompt-compile.sh** fails to load enhancement modules

The Claude Code SDK then sets a content block with empty text, which the Anthropic API rejects.

## Resolution

**Fixed in version 2.0.95** (2026-01-26):

- **validate.mdx**: Now wraps bash execution with fallback message handling
- **enhance.mdx**: Now includes pre-flight validation before agent spawn

## Workaround (For Older Versions)

If encountering this error on older versions, run the scripts directly:

```bash
# Instead of /plan:validate
bash .claude/scripts/plan-validate.sh [plan-name]

# Instead of /plan:enhance
# First compile the prompt:
bash .claude/scripts/prompt-compile.sh standard

# Then spawn manually:
bash .claude/scripts/mcp-agent-spawn.sh \
  --mode smart \
  --servers context7,supabase,sentry,linear,dash0,stripe,mux \
  --task "Enhance plan at: .claude/plans/[plan-name].md"
```

## Verification

After fix applied:

```bash
# Test with nonexistent plan
/plan:validate nonexistent-plan
# Expected: "No active plan found or validation produced no output."

# Test with empty plans directory
/plan:enhance
# Expected: "No plans found in .claude/plans/"
```

## Prevention

When creating new .mdx command files that execute bash scripts:

1. **Always capture output**: `result=$(bash script.sh 2>&1) || true`
2. **Check for empty**: `if [[ -z "$result" ]]; then echo "default message"; fi`
3. **Handle errors gracefully**: Exit with message, not silent failure

## Related Issues

- `.claude/troubleshooting/deferred-skill-cache-control.md` - Similar empty block issue with deferred skills
- [ADR-0006](../../../docs/adr/0006-documentation-automation.md) - Documents this fix

## Timeline

| Date       | Action                                          |
| ---------- | ----------------------------------------------- |
| 2026-01-25 | Issue identified during plan enhancement        |
| 2026-01-26 | Root cause analyzed                             |
| 2026-01-26 | Fix implemented in validate.mdx and enhance.mdx |
| 2026-01-26 | Troubleshooting doc created                     |

---

_Documented: 2026-01-26 | Plan: twinkling-kindling-sutherland_
