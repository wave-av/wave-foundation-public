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
| A | Spec + schema (this PR) | in progress |
| B | Aggregator script + STATE.md generator | this PR |
| C | Publish workflow template | this PR |
| D | Backfill `capabilities.json` for all 38 repos | next |
| E | CI validator wired into `_checks.yml` | next |
| F | Claude/agent grounding hook (reads state.json on session start) | next |
| G | Existing-feature rebuilds against registry (e.g. Companion module) | after F |

## Related

- `frameworks/build-on-wave/repo-manifest.json` — overlapping but smaller scope (just public surfaces). Will be superseded by `state.json` once Phase D lands.
- `frameworks/protocol-plane/README.md` — defines the layer numbering used here.
- `api-spec` repo — OpenAPI source of truth; `capabilities.json` references it.
