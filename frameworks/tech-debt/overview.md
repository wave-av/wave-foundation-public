# Tech Debt Remediation — Pre-Public Launch

> **Status:** Phase 1 Ready
> **Created:** 2026-03-26
> **Context:** Product shipped, private, all systems operational. Clearing debt before public launch.
> **Execution:** Teams-based parallel workstreams

## Tech Debt Inventory

| Category | Items | Severity | Effort |
|----------|-------|----------|--------|
| Validator violations | 863 total (transition:362, animation:280, zindex:80, shadows:79, typography:54, colors:8) | Medium | Large |
| globals.css | 4,407 lines — needs @import splitting | Medium | Small |
| ESLint consolidation | 22 .eslintrc files → unified config | Medium | Medium |
| Workspace CI | Lint, test, circular-deps failures | High | Medium |
| Security | 8 remaining vulns (moderate) | Medium | Small |
| Learning hooks | Active triggers not built | Low | Small |
| Domain docs | CLAUDE.md + AGENTS.md for service dirs | Low | Medium |
| Test coverage | No CI gate for coverage % | Medium | Medium |
| Team usage | Not leveraging parallel agents | Process | Small |

## Team Structure

```
Team: tech-debt-strike
├── team-lead (coordinator) — me
├── frontend-specialist — validator violations, globals.css, CSS tokens
├── infra-specialist — CI fixes, ESLint consolidation, test config
├── security-specialist — remaining 8 vulns, learning hooks
└── docs-specialist — domain docs, AGENTS.md, memory updates
```

## Phases

| # | Phase | Strategy | Items |
|---|-------|----------|-------|
| 1 | Quick Wins (parallel team) | Fix highest-impact, lowest-effort items | 8 |
| 2 | Validator Violation Reduction | Systematic fix of 863 violations | 6 |
| 3 | CI Pipeline Hardening | Green CI on all checks | 5 |
| 4 | Documentation + Standards | Domain docs, test gates | 5 |
| 5 | Polish + Public Readiness | Final audit before going public | 4 |

## Success Criteria

- [ ] Validator violations: 863 → <100
- [ ] CI: all required checks pass on staging
- [ ] ESLint: single unified config
- [ ] globals.css: split into <500-line modules
- [ ] Security: 0 critical, 0 high, <5 moderate
- [ ] Domain CLAUDE.md in each service dir
- [ ] Test coverage CI gate active
- [ ] Teams used for all multi-domain work
