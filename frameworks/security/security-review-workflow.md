# Security Analysis Workflow: Corridor + Serena

> **Purpose:** Combined security analysis using Corridor (plan/threat analysis) and Serena (code intelligence) for comprehensive PR and feature security review.

## Overview

Two complementary tools provide layered security analysis:

| Tool | Role | Trigger |
|------|------|---------|
| **Corridor** (`mcp__corridor__analyzePlan`) | Threat modeling, plan analysis, guardrail enforcement | Before code generation, PR review |
| **Serena** (`mcp__plugin_serena_serena__*`) | AST-aware code analysis, symbol tracing, reference finding | During code review, after changes |

## Workflow Steps

### 1. Pre-Implementation: Corridor Plan Analysis

Before writing code, analyze the plan for security risks:

```
mcp__corridor__analyzePlan({
  plan: "Description of what you're implementing"
})
```

Corridor returns:

- Threat vectors identified
- Security recommendations
- Guardrail violations (if any configured)

### 2. During Implementation: Serena Symbol Tracing

While coding, use Serena to trace security-sensitive symbols:

```
# Find all references to auth/permission functions
mcp__plugin_serena_serena__find_referencing_symbols({
  symbol_name: "withAuth",
  include_body: true
})

# Get overview of security-critical files
mcp__plugin_serena_serena__get_symbols_overview({
  relative_path: "src/middleware/auth.ts"
})

# Trace data flow through service boundaries
mcp__plugin_serena_serena__find_symbol({
  name_path: "validateRequest",
  include_body: true
})
```

### 3. Post-Implementation: Combined Review

After changes, run both tools:

**Corridor — Analyze the change plan:**

```
mcp__corridor__analyzePlan({
  plan: "Review security of: [describe changes made]"
})
```

**Serena — Verify no broken references:**

```
# Check auth guards still in place
mcp__plugin_serena_serena__find_referencing_symbols({
  symbol_name: "withRateLimit"
})

# Verify RLS policy references
mcp__plugin_serena_serena__search_for_pattern({
  pattern: "enable_rls|row_level_security",
  relative_path: "supabase/migrations/"
})
```

### 4. PR Security Checklist

For every PR touching security-sensitive code:

- [ ] Corridor `analyzePlan` run on PR description
- [ ] Serena `find_referencing_symbols` on modified auth/permission functions
- [ ] No `@ts-ignore` on security-critical types
- [ ] Rate limiting verified on new/modified API routes
- [ ] RLS policies verified on new/modified database tables
- [ ] Input validation (Zod) on all request handlers
- [ ] Error responses don't leak internal details

## Security-Sensitive Paths

| Path Pattern | Security Concern | Required Check |
|---|---|---|
| `app/api/**/*.ts` | API endpoints | Rate limiting, auth, Zod validation |
| `supabase/migrations/**` | Database schema | RLS policies, indexes |
| `src/middleware/**` | Request processing | Auth chain integrity |
| `src/lib/stripe/**` | Payment processing | Idempotency, webhook verification |
| `src/lib/supabase/**` | Database client | Service role usage, RLS bypass |

## Agent Integration

The `security-reviewer` agent combines both tools automatically:

```typescript
Task(subagent_type: "security-reviewer", prompt: "Review security of PR #NNN")
```

The `security-researcher` agent uses Corridor for threat modeling:

```typescript
Task(subagent_type: "security-researcher", prompt: "Threat model for feature X")
```

## Guardrails

Corridor guardrails are configured per-project. Check current guardrails:

```
mcp__corridor__getGuardrails()
```

Create new guardrails for recurring security patterns:

```
mcp__corridor__createGuardrail({
  name: "no-service-role-in-client",
  description: "Block service_role key usage in client-side code"
})
```

## When to Use Each Tool

| Scenario | Use |
|---|---|
| Planning a new feature | Corridor `analyzePlan` |
| Reviewing a PR for security | Both: Corridor for threats, Serena for code tracing |
| Tracing auth flow | Serena `find_referencing_symbols` + `find_symbol` |
| Checking for OWASP violations | Corridor `analyzePlan` with OWASP context |
| Verifying RLS on new tables | Serena `search_for_pattern` on migrations |
| Rename/refactor auth symbols | Serena `rename_symbol` or cclsp `rename_symbol_strict` |
