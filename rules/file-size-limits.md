---
globs:
  - "src/**/*.ts"
  - "src/**/*.tsx"
  - "app/**/*.ts"
  - "app/**/*.tsx"
  - "packages/*/src/**/*.ts"
  - "packages/*/src/**/*.tsx"
---

# File Size Limits — Two-Tier Gate System

**Small files = fast reads = better AI interconnection = LEGO block composability.**

## Two-Tier Gates

| Gate | Limit | Behavior | Justification |
|------|-------|----------|---------------|
| **Soft Gate** | 500 lines | Warning. New features go in new files. Stop adding. | Default for all services/components |
| **Hard Gate** | 800 lines | BLOCK. Must split before merge. No exceptions. | CI enforcement, pre-commit hook |

### Soft Gate (500 lines)

When a file hits 500 lines:

1. **Stop adding to it** — the next method/feature goes in a sub-service
2. Create a subdirectory (kebab-case)
3. Extract the new concern into a focused sub-service
4. Add a barrel `index.ts`

### Hard Gate (800 lines)

Files over 800 lines are blocked by CI. The ONLY exceptions:

- `*.types.ts`, `*.d.ts` — type registries are naturally large
- `generated.ts` — auto-generated files
- `events.ts` — Inngest event type registry

## Category Limits (Soft Gate)

| Category | Path Pattern | Soft Limit |
|----------|-------------|------------|
| Services | `src/services/**/*.ts` | 500 |
| Components | `src/components/**/*.tsx` | 400 |
| API Routes | `app/api/**/*.ts` | 300 |
| Lib Modules | `src/lib/**/*.ts` | 500 |
| Inngest | `src/inngest/**/*.ts` | 300 |
| Middleware | `src/middleware/**/*.ts` | 300 |

## Splitting Pattern

```
// Before: src/services/billing/HybridBillingService.ts (700 lines)
// After:
// src/services/billing/hybrid-billing/
//   ├── index.ts                    (barrel)
//   ├── SubscriptionService.ts      (~200 lines)
//   ├── InvoiceService.ts           (~200 lines)
//   └── MeterService.ts             (~200 lines)
// src/services/billing/HybridBillingService.ts (orchestrator, ~150 lines)
```

## Why This Matters

- **AI reads faster**: 300-line files use 84% less context than 1800-line files
- **Better interconnection**: small modules = more import/export edges = richer dependency graph
- **LEGO blocks**: small composable pieces snap together for any product
- **Review speed**: 300 lines = 2 min review vs 15 min for 1800 lines
- **Blast radius**: focused module changes can't break 49 other methods

## Enforcement

| Layer | Where | Gate |
|-------|-------|------|
| Rule | `.claude/rules/` | Both gates (AI sees before writing) |
| Lefthook | Pre-commit | Hard gate (800) |
| CI | GitHub Actions | Hard gate (800) |
| CodeRabbit/Cubic | PR review | Soft gate (500) warning |
| Graph | code-review-graph | Class-level detection |
