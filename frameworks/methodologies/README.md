# Methodology Catalog

The 22 methodologies wave-foundation tracks, each with a brief and a doc-path if a deeper write-up exists. The `methodology-registry.json` is the structured source of truth (scoring + categories); this catalog is the human-readable index.

## Coverage

Each methodology below is either:

- **🟢 Cataloged** — described inline here, no separate doc yet (the doc field points to this catalog with an anchor)
- **🟦 Documented** — has a dedicated doc in `frameworks/methodologies/<slug>.md`
- **⚪ Stub** — registered but not yet meaningfully described (doc: null in the registry)

The `methodology_docs_resolve` dogfood gate enforces that non-null doc paths point to a real file. The anchor (`#slug`) is informational.

## The 22

### 🟦 23. Wave Execution

Full doc: [`wave-execution.md`](./wave-execution.md). Propose → atomize → dependency-graph → wave-execute → audit. The build pattern this foundation uses on itself.

### 🟢 1. Single Source of Truth {#single-source-of-truth}

Every fact/rule/value lives in exactly one canonical place. Duplicates are either pointers (cross-references) or harvested copies in `staging/_external/` (fidelity principle, SYSTEM.md §10). Gates: `methodology_docs_resolve`, `env_registry_coverage`, `audiences_taxonomy_valid`.

### 🟢 2. DRY Audit {#dry-audit}

Periodic sweep for duplicated logic across `scripts/`, hooks, and frameworks. Detection is automatic via line-similarity on changed files; resolution is a manual call (extract vs accept). Gates: not yet (PR candidate).

### 🟢 3. SOLID for Scripts {#solid-for-scripts}

Shell scripts follow SOLID-equivalents: each script does one thing (S), exit codes follow a convention (I = interface), `set -euo pipefail` always (L = robust under failure). Gates: shellcheck ratchet, `internal_links_resolve`, `no_no_verify`.

### 🟢 4. Documentation Coverage {#documentation-coverage}

Every canonical artifact (rule, framework, gate, taxonomy) has at least one doc reference. Gates: `methodology_docs_resolve`, `required_docs_present`, `internal_links_resolve`.

### 🟢 5. Cross-Reference Integrity {#cross-reference-integrity}

Every `[link](path)` resolves. Catches doc rot before it ships. Gate: `internal_links_resolve`.

### 🟢 6. Security Audit {#security-audit}

Every PR receives bot review (CodeRabbit/Cursor/Cubic/Greptile/Sentry/Snyk/Semgrep/GitGuardian + others) + zizmor + pinact + gitleaks. Periodic threat-model review per `docs/threat-model.md`. Gates: `secret_scan`, `gitleaks_*`, `zizmor`, `pinact`, `owasp_coverage_complete`.

### 🟢 7. Error Handling Completeness {#error-handling-completeness}

Every script returns a structured exit code; every catch logs with context. The `frameworks/incident-response/` runbook template requires symptom + first action + diagnosis. Gates: shellcheck baseline (catches `|| true` swallows), zizmor (catches unguarded GHA failures).

### 🟢 8. Convention Consistency {#convention-consistency}

Naming (kebab-case for files, snake_case for shell functions), comment style (purpose-first), commit format (Conventional Commits enforced by `semantic-pr.yml`). Gates: `validate-skills` (frontmatter shape), `markdownlint_canonical`, `semantic-pr`.

### 🟢 9. Template Quality {#template-quality}

Templates in `scaffolder/templates/` + `frameworks/incident-response/runbook-template.md` pass the same gates as canonical content. Gates: `markdownlint_canonical`, `no_zero_byte_canonical`.

### 🟢 10. Hook Reliability {#hook-reliability}

Every hook is tested for happy-path + failure-injection. Hooks must be idempotent and time-bounded (timeout in hooks.json). Gates: `plugin_install_smoke`, `precommit_installed`.

### 🟢 11. Context Efficiency {#context-efficiency}

Agent context (CLAUDE.md, AGENTS.md, GEMINI.md) is < 2KB at top; deep content reached via Read. Hooks don't dump entire files. Gates: not yet — candidate for a `context_token_budget` gate.

### 🟢 12. Dependency Audit {#dependency-audit}

Renovate weekly; pinact verifies SHA pinning; zizmor flags unpinned actions; npm/pip audits run in CI. Gates: `pinact`, `zizmor`, ratchet (catches new vuln patterns).

### 🟢 13. Portability Check {#portability-check}

No hardcoded absolute home paths (e.g. `/Users/<name>/`); scripts use `$HOME`/`~`; bash compatible with macOS BSD + Linux GNU tooling. Gates: `no_hardcoded_paths`, shell-ratchet (catches GNU-only flags).

### 🟢 14. Ollama Model Quality {#ollama-model-quality}

Local 30B model (Mac Studio) handles 80%+ of agent traffic per the Token Leveragizer 5-tier (see `frameworks/model-routing/`). Periodic A/B vs hosted models. Gates: `wave_mcp_smoke`.

### 🟢 15. User Feedback Loop {#user-feedback-loop}

Every PR captures bot findings via `scripts/pr-review-extract.sh` → sticky comment + artifact. Bot Review Gate classifies by structured severity. Gates: `pr_review_smoke`, Bot Review Gate (CI).

### 🟢 16. Zero State Handling {#zero-state-handling}

Every gate handles the empty/missing-target case gracefully (return 0). Catches the dogfood-time edge where a feature doesn't exist yet but gates would otherwise hang/fail. Gates: every dogfood gate has explicit `[ -f X ] || return 0` style checks.

### 🟢 17. Automation Coverage {#automation-coverage}

47 dogfood gates + 9 required CI checks + improvement-loop nightly (4 channels). Surface area of "what's automated" is itself measured via the gate count in `wave-foundation-status.sh`. Gates: `improvement_loop_channels_wired`, all 47 dogfood gates collectively.

### 🟢 18. Plugin Integration {#plugin-integration}

Plugin auto-discovers via `hooks.json` + `plugin/skills/<name>/SKILL.md` (see `plugin/README.md` Discovery Convention section). Install simulated by `plugin_install_smoke`. Gates: `plugin_install_smoke`, `plugin_manifest_integrity`.

### 🟢 19. Knowledge Capture {#knowledge-capture}

Every PR description references the bug or finding it closes. Improvement-queue captures findings the loop surfaced. Sessions captured via the `remember` skill (separate). Gates: not yet — candidate for `pr_description_references_finding` gate.

### 🟢 20. Competitive Analysis {#competitive-analysis}

Periodic review of `staging/_external/wsc-docs/evaluations/` and similar (Vercel sandboxes, Mux, ElevenLabs, etc.). Drives env-registry growth. Gates: `env_registry_coverage` (catches "we built against a tool not documented").

### 🟢 22. Agent Commerce {#agent-commerce}

Agents transact via spend-authority tokens (Phase 3 of the identity+money program). Direct rail-key access is a policy violation. Gates: `spend_authority_gate`, `identity_policy_audit`.

## Why 22 (not 21)

Methodology #21 was the original "Agent Commerce" ID; it was reassigned to #22 to avoid a numbering collision after a parallel sub-project. The reassignment is captured in commit `8da33ef`. Wave Execution slots in as #23.

## Adding a methodology

1. Add a row to `methodology-registry.json` with `id` (max+1), `name`, `category`, `impact`, `cost`, `phases`, `description`, `doc`
2. Either inline a section in this catalog with a `#slug` anchor, or create `frameworks/methodologies/<slug>.md` and point `doc` at it
3. `methodology_docs_resolve` enforces the doc path resolves
4. Add a row to this catalog (alpha order; this guide is human-readable)

## Cross-references

- [`methodology-registry.json`](../../methodology-registry.json) — structured source
- [`wave-execution.md`](./wave-execution.md) — the one fully-documented methodology
- `docs/threat-model.md` (lands in PR U) — security audit (#6) anchor
- [`frameworks/improvement-loop/README.md`](../improvement-loop/README.md) — automation coverage (#17) anchor
