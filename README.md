# wave-foundation

The single source of truth for **how we build** across every WAVE project — rules, frameworks,
design system, and the executable agent tooling (hooks, skills, eval gates). Private.

## The principle: consumed, not copied

Today the shared stuff is scattered and drifts:

| Where it lives now | What's there | Problem |
|---|---|---|
| `claude-hub` | AGENTS.md, projects.json, methodology-registry, templates | on a personal GH, not `wave-av` |
| `claude-protocol-suite/skills` | custom Claude Code skills | ⚠️ **not git, no remote, unbacked-up** |
| `~/.claude/{rules,hooks,agents,plugins}` | live agent infra | machine-local, hand-edited, no version |
| each project (burnrate, dispatch, wave-surfer-connect) | **copies** of the above | drift — fix a rule in one, the others rot |

`wave-foundation` ends the copying. Projects **pull** from one versioned source:

- **Executable** (hooks, skills, eval gate, CI-review) → shipped as a **Claude Code plugin**, installed across projects. Update once, every project gets it.
- **Docs/rules** (build conventions, UX-writing, security, design tokens) → consumed by reference / git submodule / a tiny sync script. Version-pinned.
- **Attested** → projects can assert which `wave-foundation` version they're on (the same deployed==source hash pattern dispatch uses, #83).

## Layout

The canonical, consumed-by-projects foundation lives at the repo root. Everything still being
harvested from other repos sits under `staging/` until it's curated and promoted up.

**Canonical (the foundation):**

```text
plugin/          THE installable Claude Code plugin — 8 guard hooks + 5 plan skills. The only shipped artifact.
rules/           cross-project MUST/NEVER rules (the rule-pack)
frameworks/      30+ consumable standards — identity-money (5-phase user/credential/payment/audit/anomaly), claude-api, observability, methodology engine, eval gate, improvement-loop (see CONSUME.md catalog)
design-system/   OKLCH color rules + token sets
scripts/         consume.sh + dogfood.sh + sync + status tooling
taxonomy/        skills/agents/products/audiences/queues/voice-roles taxonomies
schemas/         JSON-Schemas (skill frontmatter)
docs/            env-registry, improvement-queue, open-core-publish runbook, superpowers specs
methodology-registry.json  22-method priority-scoring engine
```

## Self-applied posture

The foundation is **its own first consumer**. Every gate it asks consumers to pass, it passes itself:

- **47 self-applied dogfood gates** in `scripts/dogfood.sh` (re-runnable; pass = green, fail = open issue)
- **9 required CI checks** on every PR (secret-scan, file-size, skill-validate, gate/checks, gate/skill-validate, pinact, version-sync, shell ratchet, python ratchet)
- **Improvement loop** — 4 feed-forward channels: ratchet auto-shrink, dogfood failures → queue, PR-review findings → queue, bot-suggestion sticky comments (nightly cron)
- **Metrics ledger** — every gate emits NDJSON; weekly summary issue surfaces never-failed (promote-to-required) + high-fail-rate (tune-or-drop) candidates
- **Open-core publish path** — `scripts/sync-public.sh` audit currently reports `publishable: 95, held: 0` (ready to mirror)

One-command snapshot: `bash scripts/wave-foundation-status.sh` (or `--json` for tooling).

**`staging/` (harvested, not yet consumed):**

Material lifted (copied, never moved) from `wave-surfer-connect`, `claude-hub`,
`router-dispatch-test`, `~/.codex`, and `~/.claude` — skills, agents, commands, hooks, configs,
docs, product specs, MCP profiles, observability, and more. Promote items to the root as they're
curated; treat everything under `staging/` as un-vetted harvest until then.

**Meta:**

```text
CLAUDE.md        how to work in this repo
SYSTEM.md        how the gates / CI / auto-merge / taxonomies fit together
CONSUME.md       how a project adopts wave-foundation (3-layer pattern)
MIGRATION.md     provenance — what came from where
BACKLOG.md       everything in flight (harvest waves logged)
```

A WAVE thing. Open-core note: a generic subset (file-size gate, design-system, UX-writing) can be
extracted public later, like dispatch-edge; business-specific rules stay private.
