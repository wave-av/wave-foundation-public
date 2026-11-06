# platform-registry

**The canonical, machine-readable map of every WAVE repo, what it exposes, what it consumes, and how it fits the protocol plane.**

Every wave-av repo publishes a `capabilities.json` at the root on every push to master. A reusable workflow in this framework aggregates them into a single `STATE.md` + `state.json` in this repo, which becomes the **ground truth that every agent / PR review / CI gate reads from before doing meaningful work**.

The cost of NOT having this: every new feature is built against somebody's snapshot of the platform, which is always stale. Companion modules end up listing actions that don't exist; SDK docs reference endpoints that moved; threat models cite defenses that were refactored away. We just lived through this — the existing `companion-module-wave` README listed actions for products that were never built.

## What problem this solves

> "How does every system have awareness of every other system?"

Three layers, smallest to largest:

| Layer | What | Where |
|---|---|---|
| **Discovery** | "What repos/products exist? Which plane layer is each in?" | `STATE.md` (human-readable, generated) |
| **Contract** | "What API does each one expose? What does it consume?" | `state.json` (machine-readable, generated) + each repo's `capabilities.json` (source) |
| **Grounding** | "Build against the current view, not your snapshot" | hook injects `state.json` at session start; CI ratchets against the registry |

## How it works

```
┌─ each wave-av repo ──────────────────────────┐
│  /capabilities.json    (source of truth)     │
│  /.github/workflows/publish-capabilities.yml │
│    └─ on push to master:                     │
│       upload to gh-pages branch              │
│       OR open an issue to wave-foundation    │
└───────────────────────┬──────────────────────┘
                        │
                        ▼
┌─ wave-foundation ─────────────────────────────┐
│  frameworks/platform-registry/                │
│   ├─ aggregate.ts → reads all capabilities    │
│   ├─ state.json   (machine — pinned per SHA)  │
│   ├─ STATE.md     (human — auto-generated)    │
│   └─ scripts/validate-against-registry.ts     │
│        └─ used by CI in every consumer repo   │
└───────────────────────────────────────────────┘
```

## Why this matters NOW

We just shipped Layer 0 (Operator) with 6 new repos in a single session. The Companion module README we wrote months ago still references a "WAVE Cloud Switcher" — but what we actually shipped is closer to a protocol-plane operator console. Without the registry, every cross-repo feature has to manually re-read 38 READMEs to figure out what's current. That doesn't scale.

## What's in this framework

| File | Purpose |
|---|---|
| `schema/capabilities.schema.json` | JSON Schema for every repo's `capabilities.json` |
| `examples/capabilities.example.json` | Annotated example for new repos |
| `examples/per-layer-examples.md` | One full example per protocol-plane layer (0..4) |
| `scripts/aggregate.ts` | Reads every repo's `capabilities.json`, emits `state.json` + `STATE.md` |
| `scripts/validate.ts` | Validates a `capabilities.json` against the schema (used by CI) |
| `scripts/check-drift.ts` | Existence drift — declared version / CLI binaries / cross-refs must actually exist |
| `scripts/check-honesty.ts` | **Enforcement drift (anti-vaporware)** — `metered:true` / real `auth` claims must be backed by source or a gateway front |
| `workflows/publish-capabilities.yml` | Reusable workflow each repo includes |
| `workflows/registry-aggregate.yml` | Foundation-side aggregator (runs daily + on each repo's push) |
| `STATE.md` | Generated — current snapshot of the whole platform |
| `state.json` | Generated — same data, machine-readable |

## Capability dimensions

A repo's `capabilities.json` describes:

- **Identity**: repo, plane-layer (0-4 or null for non-plane), foundation-pin, version
- **Exposes**: HTTP/RPC endpoints (OpenAPI ref), CLI commands, MCP tools, hardware drivers, render surfaces
- **Consumes**: Other WAVE products it calls, third-party services, foundation frameworks, hardware
- **Events**: Topics published, topics subscribed (eventbus, Sentry tags, x402 meters)
- **Status**: Lifecycle (alpha/beta/ga/sunsetting), maintainer team, on-call rotation

Every field is optional except `repo`, `version`, and `lifecycle`. The schema is permissive on day 1 so backfill is fast; tightening happens incrementally.

## Grounding contract

Every PR-opening agent + CI gate MUST:

1. Read `state.json` from foundation HEAD.
2. Reject claims about products / endpoints / events that don't exist in the registry.
3. When introducing a new capability, update the repo's `capabilities.json` in the same PR.

The `validate.ts` script is wired into `_checks.yml` and refuses to merge a PR that adds an endpoint/CLI/MCP tool without updating `capabilities.json` to match.

## Roadmap

| Phase | Work | Status |
|---|---|---|
| A | Spec + schema | **shipped** (#273) |
| B | Aggregator script + STATE.md generator | **shipped** (#273, workflow #296) |
| C | Publish workflow template | **shipped** (#273) |
| D | Backfill `capabilities.json` for all 49 repos | **13 merged, 36 in review** |
| E | CI validator + drift checker | **this PR** |
| F | Claude/agent grounding hook (reads state.json on session start) | **shipped** (#327) |
| G | Existing-feature rebuilds against registry (e.g. Companion module) | in review (`wave-av/companion-module-wave` PR #4) |

## Phase F — agent grounding hook (shipped #327)

`scripts/ground-agent.sh` reads `state.json` and emits a markdown briefing of the whole platform — every repo, version, lifecycle, layer. Designed to be dropped into a Claude Code `SessionStart` hook so future agent sessions ground against current reality **before the first user turn**.

[`hooks/claude-session-start.md`](./hooks/claude-session-start.md) documents the 6-line install. Once wired, every session starts with a briefing like:

```
# WAVE platform state (loaded for agent grounding)
_Repos:_ 7

## Grounding rules (Rule 1: read this before claiming any WAVE capability exists)
- A WAVE repo, product, endpoint, or MCP tool is real only if it appears here.
...

## Layer 0 — Operator
- wave-av/wave-desktop (0.2.0, alpha) — operator · public · electron · on-prem
...
```

Together with Phase E's CI validator, this closes the loop: **prevention** at session start + **detection** at PR open. Both feed off the same `state.json`.

#327 seeded `state.json` + regenerated `STATE.md` from the 7 currently-merged `capabilities.json` files. The aggregator workflow (#296) takes over from this point.

## Phase E — drift checks (added this PR)

`scripts/check-drift.ts` catches the three most-flagged classes of error bots find on `capabilities.json` PRs:

| Flag | Check | Catches |
|---|---|---|
| `--check-package-version` | `version` field matches `package.json` / `Cargo.toml` / etc. | "manifest version `0.3.0` ≠ package.json `1.0.2`" |
| `--check-cli-binaries` | declared `exposes.cli[].binary` resolves to a real `package.json#bin` entry or `cmd/<name>/` directory | "declared CLI binary `my-cli` not found in any executable surface" |
| `--check-cross-refs` | each `consumes.waveProducts[].repo` exists in foundation's `state.json` | "references `wave-av/wave-ghost-producer` but that repo is not in the registry" |

`.github/workflows/validate-capabilities.yml` is the reusable workflow that bundles schema validation + drift checks. Wire it into a consumer repo by adding:

```yaml
# .github/workflows/capabilities.yml
name: capabilities
on: { pull_request: {}, push: { branches: [main, master] } }
jobs:
  validate:
    uses: wave-av/wave-foundation/.github/workflows/validate-capabilities.yml@v1
    with:
      check_package_version: true
      check_cli_binaries: true
      check_cross_refs: true
```

The workflow is a no-op for repos without `capabilities.json` — they opt in by adding the file.

## Phase F — honesty checks (anti-vaporware)

`check-drift.ts` proves a declared thing *exists*. `scripts/check-honesty.ts` proves a declared
thing is *true*: an `exposes.apis[]` entry that claims `metered: true` or a real `auth` (anything
but `"none"`) must actually be backed.

This exists because a 2026-06-07 protocol sweep found the NDI / OMT / SRT spoke manifests all
advertising `metered: true` + enforcing `auth` over surfaces that enforced nothing — bare 501 stubs
and a copy-pasted NDI manifest. The agent-facing discovery layer was lying. This is exactly the
failure mode this whole framework was built to stop (companion modules listing actions that were
never built), one layer deeper: claiming *enforcement* that was never wired.

Per claimed API, **honest** iff EITHER:

- the repo's own source backs the claim — emits usage (`POST /v1/internal/usage`, a `wave-usage`
  response header, `recordUsage`, a `MetricsCollector`) or challenges payment (x402 / `402`) for
  `metered`; checks a credential / principal (`Authorization`, `x-wave-*`, `authorize()`, 401/403)
  for `auth`; **OR**
- it's a genuine gateway-fronted spoke: `consumes.waveProducts` declares the configured gateway repo
  **and** its source reads the gateway-injected principal (`x-wave-org` / `x-wave-tier` / …). The
  gateway enforces auth + metering at the edge, so a real fronted spoke needn't repeat it — but a
  bare stub that merely *lists* the gateway without wiring the principal does not qualify (closes
  the "add the gateway to consumes and keep lying" bypass).

The heuristic is biased to avoid false alarms (broad evidence patterns): a missed lie is a
follow-up, a false failure blocks an honest repo. It is wired into `validate-capabilities.yml`
**advisory by default** (`honesty_enforce: false` → surfaced, not blocking); flip `honesty_enforce: true`
per-repo once the manifest is clean. The honest fix for a not-yet-real surface is to say so:
`metered: false`, `auth: "none"`, until the enforcement actually ships. Run it locally with
`tsx scripts/check-honesty.ts capabilities.json` (or `--self-test` for the fixtures).

## Related

- `frameworks/build-on-wave/repo-manifest.json` — overlapping but smaller scope (just public surfaces). Will be superseded by `state.json` once Phase D lands.
- `frameworks/protocol-plane/README.md` — defines the layer numbering used here.
- `api-spec` repo — OpenAPI source of truth; `capabilities.json` references it.
