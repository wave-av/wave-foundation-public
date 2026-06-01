# Security Scanner Framework

Three layers of static security analysis the foundation expects every consumer to wire. Each catches a different failure mode, so they don't substitute — they compose.

| Scanner | Catches | Cost | Required |
|---------|---------|------|----------|
| **Secret scanning** | hardcoded credentials | $0 (gitleaks + grep) | yes (`secret-scan` gate) |
| **SAST: pattern-based** (Semgrep) | known anti-patterns by signature | $0 (community rules) | yes (`semgrep` in pre-commit, optional in CI) |
| **SAST: dataflow** (CodeQL) | injection, taint flows, query-pair vulnerabilities | $0 (public repos), GHAS license (private) | **recommended** |
| **Dependency scanning** | known CVEs in deps | $0 (npm audit, pip-audit, dependabot) | yes (`pinact` + dependabot) |
| **Dependency confusion** | hijack vectors via floating/internal-scope deps | $0 (`check-dependency-confusion.sh`) | yes (`dependency_confusion_gate`) |

This README covers the **CodeQL / GHAS** layer — the dataflow analyzer that catches what the others can't. See `rules/dependency-confusion.md` for #5, and `docs/threat-model.md` for the full mapping.

## When CodeQL pays off

CodeQL is a query language over a code's flow graph. Three patterns are worth its weight:

1. **Path traversal** — user input reaches `fs.readFile(...)` with no normalization in between
2. **SQL injection** — user input concatenates into a query string (vs. parameterized)
3. **SSRF** — user input determines a fetch URL with no host allowlist

Pattern scanners (Semgrep) match syntax. CodeQL follows variables across function boundaries, so a sanitizer in another file is recognized as legitimate. The downside: it's slow (5–15 min on a typical repo) and requires a database build step.

## Wiring CodeQL into a consuming repo

`examples/workflows/codeql.yml` is a reference workflow. Copy into `.github/workflows/codeql.yml` and adjust the languages list.

Key config:

- `paths-ignore` excludes `staging/_external/` (fidelity-preserved harvest)
- `category: /language:${{matrix.language}}` so multi-lang runs don't collide in code-scanning UI
- `queries: security-extended` adds queries beyond the default `security-and-quality` set
- Schedule (weekly) catches drift between PRs

## GHAS vs CodeQL on public repos

- **Public repos**: CodeQL is free; results show under "Security → Code scanning."
- **Private repos**: requires GitHub Advanced Security (GHAS) license (paid). Without it, only the default Dependabot + secret-scanning are available.

For wave-foundation (public) the workflow runs free. For private consumer repos without GHAS, wire Semgrep + gitleaks + dependabot as the affordable substitute.

## Custom queries (optional)

For project-specific patterns (e.g., "never call `internal-api` from edge runtime"), write a `.ql` query and reference it in the workflow's `queries:` field. Most consumers don't need this; the security-extended pack covers ~95% of real findings.

## What about Snyk / Sonar?

- **Snyk Open Source**: same dep-CVE scope as `npm audit` + Dependabot. Free tier ok for hobby use; paid only buys triage UI. Not required.
- **SonarCloud**: code quality + some security. Heavier overlap with Semgrep. Optional for consumers who want a single dashboard.

The foundation does NOT require these because their incremental value over the free stack is real-but-small and they introduce vendor lock-in.

## Cross-references

- [`examples/workflows/codeql.yml`](../../examples/workflows/codeql.yml) — reference workflow
- [`docs/threat-model.md`](../../docs/threat-model.md) — full OWASP/threat coverage matrix
- [`rules/dependency-confusion.md`](../../rules/dependency-confusion.md) — supply-chain gate (#5 above)
- [`scripts/dogfood.sh`](../../scripts/dogfood.sh) — `secret_scan` + `pinact` + `dependency_confusion_gate` are dogfooded
