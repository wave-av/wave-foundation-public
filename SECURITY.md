# Security Policy

## Reporting a vulnerability

This is a private WAVE foundation repository. If you find a security issue — a leaked
credential, an unsafe hook, a workflow injection, or anything that could affect a consuming
WAVE project — report it privately:

- Email: <jake@wave.online>
- Or open a GitHub Security Advisory (Security → Advisories → Report a vulnerability)

Do **not** open a public issue or PR that discloses the details.

## What this repo enforces

Because `wave-foundation` is consumed by other projects, its own pipeline is gated:

- **Secret scanning** — gitleaks at commit (pre-commit) and in CI (`self-check.yml`), allowlist-aware.
- **Workflow security** — `actionlint` + `zizmor` analyze every GitHub Actions workflow.
- **Shell safety** — `shellcheck` lints hook scripts.
- **Frontmatter integrity** — `scripts/validate-skills.py` validates every `SKILL.md`.
- **Dependency review** — `dependency-review` + Renovate (SHA-pinned actions, security auto-merge).

## Supported

Only the latest `master` is supported. Pin to a tag/SHA when consuming.
