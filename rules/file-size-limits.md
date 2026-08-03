---
globs:
  - "src/**/*.ts"
  - "src/**/*.tsx"
  - "app/**/*.ts"
  - "app/**/*.tsx"
  - "packages/*/src/**/*.ts"
  - "packages/*/src/**/*.tsx"
  - ".claude/scripts/**/*.sh"
---

# File Size Limits — Two-Tier Gate System

**Small files = fast reads = better AI interconnection = LEGO block composability.**

## The Gate Is an Architecture Signal — Never Trim Context to Pass It (LAW)

A size gate exists so we **build correctly**. When a file hits or nears a gate, that is the system
telling you the file is doing too much — the ONLY acceptable response is to **DECOMPOSE**: extract a
cohesive concern into its own module/stage (see the Splitting Pattern below), or put new logic in the
*right* module so the host file barely grows.

**NEVER remove comments, docstrings, blank lines, or explanatory context to slip a file under the
number.** That yields a file that is shorter but *less* understandable — the exact opposite of why the
gate exists — and is a violation, not a fix. An obstacle is a forcing function to make you think
efficiently and effectively (restructure); it is never something to satisfy lazily by deleting context.

> Putting new logic in the right module so the host file barely changes is the move. Shortening a doc
> comment to win a line is the anti-pattern.

This is **LAW** (`CORE-RULES.md`), recorded from a real correction (`behavioral-rules.md`), and a direct
expression of composability (`composability-philosophy.md`). Enforced by CI
(`scripts/check-context-integrity.sh` flags context trimmed to pass a gate), the soft early-warning, and
review — see **Enforcement** below.

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

**First-party code — the code we own — is held to 800.** A file over 800 is blocked by CI; the
response is to **DECOMPOSE** (extract a cohesive module/stage), NEVER to trim comments/context to slip
under the number (that is the violation this rule exists to prevent — see "The Gate Is an Architecture
Signal" below). There is **no foundation-only ceiling**: the same 800 the rule declares and spokes
inherit applies to wave-foundation itself (the former `max_lines: 1000` loophole is closed, #79).

**Scope — what is gated:** `*.ts`, `*.tsx`, `*.js`, `*.py` everywhere; `*.sh` is gated on
wave-foundation (`self-check.yml`). Spoke `.sh` gating is a deliberate, phased rollout (each spoke's
shell must land under 800 first), so the reusable `checks.yml` does not yet gate `.sh`.

**Exempt BY PATH — `staging/`:** vendored / harvested material under `staging/` (e.g.
`staging/_external/**`) is NOT first-party and is exempt by a PATH rule in every enforcer
(`case staging/*`), not by a hand-maintained enumeration. Faithful upstream beats forced
decomposition there; when a file is promoted out of `staging/` to the canonical tree it becomes
first-party and the 800 cap applies.

**The only other exceptions** (naturally-large code, excluded by suffix/name):

- `*.types.ts`, `*.d.ts` — type registries are naturally large
- `generated.ts` — auto-generated files
- `events.ts` — Inngest event type registry

`.github/.filesize-allowlist` remains for a **rare, auditable first-party** exception (keep it
near-empty) — never a parking lot for files that should be split.

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
| CI | GitHub Actions | Hard gate (800), **first-party only** (`staging/` vendored exempt by path); `.sh` gated on foundation; + soft early-warning at 85% of cap (plan a split before the wall) |
| CI (anti-trim) | `scripts/check-context-integrity.sh` | Flags context REMOVED to pass a gate (decompose, don't trim); allowlist `.github/.context-trim-allow` |
| CodeRabbit/Cubic/Greptile/Corridor | PR review | Soft gate (500) warning; Corridor flags large files as attack surface |
| Graph | code-review-graph | Class-level detection |

**Automated PR creators** (one-shot pipeline, Cursor bot, Dependabot, WAVE BugBot) MUST run
`bash scripts/check-file-size.sh --ci` before opening a PR and split any over-limit file first —
no human, AI, or bot should produce a file over the category limits. Four layers (write → commit →
PR → review), zero escape paths.
