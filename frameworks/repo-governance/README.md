# frameworks/repo-governance

The enforceable standard for **what every wave-av repository must have** — files and gates — so that
every repo, public or private, human- or agent-facing, is correct, protected, and consistent.

## Pieces

- **[`governance-matrix.md`](./governance-matrix.md)** — the spec: required files × required gates,
  across visibility (`public`|`private`) and audience (`human`|`agent`). The source of truth.
- **[`repo-governance-check.sh`](./repo-governance-check.sh)** — verify ONE repo against the matrix
  (files in a checkout, and — with `--remote owner/repo` — branch protection + required status checks).
- **[`governance-audit.sh`](./governance-audit.sh)** — sweep the whole org and print a gap report
  (remote-only; uses the community-profile, contents, and protection APIs).

## How it fits the system

- **Org defaults, not copies.** GitHub applies community-health files from the org `wave-av/.github`
  repo to every repo that lacks its own — so `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
  issue/PR templates, and the org `AGENTS.md` are set **once** and cover all repos. A repo keeps its own
  copy only to override.
- **Gates via org rulesets.** Branch protection + required status checks are applied with an org-level
  ruleset, not per-repo clicking — one config, every repo.
- **Multiple independent gate types.** Security (secret-scan, SCA, scorecard), quality (lint, typecheck,
  test, file-size), review (CODEOWNERS, CodeRabbit), supply-chain (provenance, SBOM) — so no single
  failure mode passes unnoticed. Public repos carry the stricter superset.
- **Human ⇄ agent.** Every repo ships both a human entry (`README.md`) and an agent entry (`AGENTS.md`);
  copy passes the [copywriting gate](../copywriting/) with the right voice for each audience.

## Usage

```bash
# audit the whole org
./governance-audit.sh wave-av

# check one repo's files + live gates
./repo-governance-check.sh --remote wave-av/dispatch-edge --kind service

# check a local checkout before opening a PR
./repo-governance-check.sh --dir . --visibility public --strict
```

CI wires `repo-governance-check.sh` as a required gate; `governance-audit.sh` runs on a schedule and
opens issues for new gaps.
