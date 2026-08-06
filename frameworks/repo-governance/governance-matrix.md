# WAVE repo-governance matrix

The single source of truth for **what every wave-av repository must have** — files and gates — across
two axes: **visibility** (`public` | `private`) and **audience** (`human` | `agent`). Enforced by
`repo-governance-check.sh` (per repo) and swept org-wide by `governance-audit.sh`. Defaults that apply
to *every* repo live in the org `wave-av/.github` repo; a repo only needs its own copy when it overrides.

Copy in any of these files must pass the [copywriting gate](../copywriting/) — **human** docs are warm and
benefit-led; **agent** docs are terse and contract-led (the human⇄agent taxonomy).

## Required files

| File | private | public | audience | Notes |
|---|:--:|:--:|:--:|---|
| `README.md` | ✅ | ✅ | human | Entry point. Public: no internal hostnames/secrets/dashboards. |
| `AGENTS.md` | ✅ | ✅ | agent | How an agent should work in this repo (build/test/gates/PR rules). Org default covers repos without one. |
| `SECURITY.md` | ✅ | ✅ | human | Vuln-reporting policy (private: internal channel; public: <security@wave.online> + disclosure window). |
| `CODEOWNERS` | ✅ | ✅ | — | Review routing; backs the CODEOWNERS-review gate. |
| `.coderabbit.yaml` | ✅ | ✅ | — | Review automation (CodeRabbit review config; approvals are vendor-side, not set here). |
| `CHANGELOG.md` | ✅ | ✅ | human | [Keep a Changelog](https://keepachangelog.com); `Unreleased` section maintained. |
| `.github/ISSUE_TEMPLATE/` + `PULL_REQUEST_TEMPLATE.md` | ✅ | ✅ | human | Org default applies unless overridden. |
| `LICENSE` | — | ✅ | — | **P0 for public.** SPDX-identified. |
| `CODE_OF_CONDUCT.md` | — | ✅ | human | Org default. |
| `CONTRIBUTING.md` | — | ✅ | human | How to propose changes; links the gates. |
| `SUPPORT.md` | — | ✅ | human | Where to get help. |
| `llms.txt` | ➖ | ➖ | agent | Required for **deployed services / SDK** repos (agent discovery). |
| `skill.md` / `openapi.*` | ➖ | ➖ | agent | Required where the repo IS an API/SDK surface. |

✅ required · ➖ required when the repo is that kind (service/SDK) · — n/a

## Required gates (status checks + protection)

Multiple **independent** gate types, so a single failure mode never passes unnoticed. Branch protection is
applied via an **org-level ruleset** (PR required · required status checks · `enforce_admins` on · ≥0
approving reviews). No bot auto-approval satisfies the review requirement; when approving reviews are
required, they must come from a human or CODEOWNERS reviewer.

| Gate | type | private | public |
|---|---|:--:|:--:|
| Branch protection (PR-required, enforce_admins, linear) | protection | ✅ | ✅ |
| CODEOWNERS review | review | ✅ | ✅ |
| CodeRabbit review gate | review (AI) | ✅ | ✅ |
| Secret scan (push + PR) | security | ✅ | ✅ |
| SCA / dependency audit (Socket or semgrep) | security | ✅ | ✅ |
| Lint | quality | ✅ | ✅ |
| Typecheck (if TS) | quality | ✅ | ✅ |
| Tests (if present) | quality | ✅ | ✅ |
| File-size ratchet | quality | ✅ | ✅ |
| Copywriting gate (if human copy) | quality | ✅ | ✅ |
| OpenSSF Scorecard | security | — | ✅ |
| Dependency review (PR) | security | — | ✅ |
| Build provenance / SLSA on release | supply-chain | — | ✅ |
| License/SBOM check | compliance | — | ✅ |
| Ambiguity Gate (PR-body checklist + advisory CI) | advisory | ➖ | ➖ |

`advisory` = surfaced, never merge-blocking. The **Ambiguity Gate**
([`frameworks/ambiguity-gate/`](../ambiguity-gate/)) is a PR-template checklist plus an advisory
`semantic-pr.yml` step (`continue-on-error`, per `DECISIONS.md` ADR-006) that flags a missing gate or a
hard-to-reverse / public↔private-boundary action with no linked ADR. Recommended for every repo with a PR
template; not a required status check.

## Public-repo P0 (exposure risk)

A public repo is **non-compliant-critical** if it lacks any of: `LICENSE`, `SECURITY.md`, secret-scan,
SCA. These are fixed first — a public repo without them is an active risk, not a backlog item.

## Changelogs · updates · marketing

- **CHANGELOG.md** in every repo (Keep a Changelog); releases cut from the `Unreleased` section.
- **Public** repos: release notes published on tag (provenance attached); marketing/README copy passes the
  copywriting gate and carries the human⇄agent dual framing where the repo is a product surface.
- **Agent-facing** updates (AGENTS.md / llms.txt / skill.md) are versioned alongside human docs — never
  one without the other.
