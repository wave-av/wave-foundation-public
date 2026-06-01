# TechDebt Remediation Framework

Systematic approach to clearing technical debt before public/major launches.

## Source

Harvested from `wave-surfer-connect/.claude/plans/tech-debt-remediation/`. This is a live plan template — adapt phases for your project's specific debt inventory.

## Structure

```
tech-debt/
  overview.md              — Inventory, team structure, phase summary, success criteria
  manifest.json            — Machine-readable plan state (phases, velocity, tags)
  01-quick-wins.md         — Phase 1: High-impact, low-effort items (parallel team)
  02-validator-reduction.md — Phase 2: Systematic validator violation fix
  03-ci-hardening.md       — Phase 3: CI pipeline green on all checks
  04-documentation-standards.md — Phase 4: Domain docs + standards
  05-polish-public-ready.md — Phase 5: Final audit before go-public
```

## Team Pattern

Always use `tech-debt-strike` team structure:

```
Team: tech-debt-strike
├── team-lead (coordinator)
├── frontend-specialist — CSS/UI violations, component standards
├── infra-specialist — CI, config, build tooling
├── security-specialist — vulns, auth, compliance
└── docs-specialist — CLAUDE.md, AGENTS.md, domain docs
```

## Inventory Categories (from WAVE example)

| Category | Detection Tool | Fix Strategy |
|----------|---------------|-------------|
| Validator violations | `scripts/validate-*.js` | Batch autofix by domain |
| Giant files | `check-file-size.sh` | Split at service/component boundaries |
| ESLint fragmentation | `find . -name ".eslintrc*"` | Consolidate to root config |
| CI failures | GitHub Actions | Fix each check type |
| Security vulns | `pnpm audit` | Update deps, patch CVEs |
| Missing RLS | Supabase MCP | Add policy per table |
| No domain docs | `find . -name "CLAUDE.md"` | Add per service dir |
| Test coverage gaps | `npx vitest --coverage` | Add gate in CI |

## Success Criteria Template

Adapt these per project:

- [ ] Validator violations: N → <100
- [ ] CI: all required checks pass on staging
- [ ] ESLint: single unified config
- [ ] Largest files: all under 800 lines
- [ ] Security: 0 critical, 0 high
- [ ] Domain CLAUDE.md in each service dir
- [ ] Test coverage CI gate active

## Running the Plan

```
/plan:to-action frameworks/tech-debt/overview.md  → creates atomic tasks
/plan:execute                                       → execute waves
Team: tech-debt-strike                              → spawn parallel agents
/audit:execution                                    → verify before PR
```
