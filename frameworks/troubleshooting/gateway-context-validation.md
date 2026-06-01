# Gateway Context Validation Error (Claude Code 2.1.27)

## Symptom

Context management validation error when using Claude Code with:

- AWS Bedrock
- Google Vertex AI
- Other gateway providers

Error may appear as:

- "Context validation failed"
- "Beta header validation error"
- "Experimental feature not supported"

## Solution

Set environment variable:

```bash
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1
```

Or add to `.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1"
  }
}
```

## Root Cause

Experimental beta features may not be supported by all gateway providers. The 2.1.25 release fixed beta header validation for gateway users, and 2.1.27 ensures `DISABLE_EXPERIMENTAL_BETAS=1` properly avoids the validation error.

## Verification

After setting the environment variable:

1. Restart Claude Code
2. Verify the setting:

   ```bash
   claude --version
   # Should show 2.1.27
   ```

3. Check settings applied:

   ```bash
   jq '.env.CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS' .claude/settings.json
   # Should show "1" or "0"
   ```

## When to Use

Enable this escape hatch (`=1`) if:

- Using Claude Code with AWS Bedrock
- Using Claude Code with Google Vertex AI
- Experiencing gateway-related validation errors
- Using Claude Code through API gateways or proxies

Leave disabled (`=0`) if:

- Using direct Anthropic API
- No gateway-related errors
- Want access to experimental features

## Related Resources

- Claude Code 2.1.25 Release Notes
- Claude Code 2.1.27 Release Notes
- `.claude/rules/06-ai/gateway-routing.md` - Gateway routing rules
- `docs/integrations/AI-GATEWAY.md` - Full gateway documentation
