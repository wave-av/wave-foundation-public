# Agent grounding contract

> "How do we ensure every agent/PR/CI gate has full awareness of the current platform?"

The platform-registry exists so the answer can be **one file**: `state.json`. Anywhere a decision is being made about the platform — a Claude session, a PR review bot, a CI workflow gate — that decision must be grounded against the registry, not against the agent's training/memory snapshot.

## The grounding rules

### Rule 1: Read `state.json` before claiming a capability exists

If a PR / doc / commit message references a WAVE product, endpoint, MCP tool, hardware driver, or eventbus topic, the registry MUST contain a matching entry. Otherwise the reference is fabricated and the PR is rejected.

The check is mechanical:

```ts
const state = JSON.parse(await fs.readFile('state.json', 'utf8'));
const exists = state.capabilities.some((c) => c.repo === claimed);
if (!exists) reject(`unknown repo: ${claimed}`);
```

This is what catches drift like "the Companion module references `recall_preset` for a Cloud Switcher that was never built."

### Rule 2: Update `capabilities.json` in the same PR that ships the capability

A PR that adds a new endpoint, CLI command, MCP tool, or eventbus topic without updating `capabilities.json` is incomplete. The CI validator refuses to merge.

This is the inverse of Rule 1 — it keeps the registry from going stale.

### Rule 3: When two repos disagree, foundation HEAD wins

If a consumer's `capabilities.json` says it calls the gateway's `/v3/feed/{slug}` but the gateway's `capabilities.json` only exposes `/v4/feed/{slug}`, the aggregator emits a `consumes-without-exposes` finding. CI in the consumer repo blocks until it's reconciled.

### Rule 4: Agents read on session start

Every Claude session that touches WAVE repos:

1. Reads `wave-foundation/frameworks/platform-registry/state.json` from the consume.sh-vendored `.foundation/` tree.
2. Surfaces a one-line summary in the session context: "current platform: N repos across X layers, foundation v1 @ <sha>".
3. Treats anything not in `state.json` as nonexistent until Rule 2 lands.

Implementation: a post-`consume.sh` hook that writes a context-injection file the session start logic reads. Phase F builds this.

## What this kills

Without grounding, every session relives the same mistake: building against an outdated worldview. Concrete examples this prevents:

- Companion module README listing "WAVE Cloud Switcher" actions that were never built (the trigger for this entire framework).
- SDK examples referencing endpoints that moved during a deprecation window.
- Threat models citing defenses that were refactored away.
- Agent dispatch routing requests to MCP tools that no longer exist.

## What this doesn't replace

- Free-form prose docs (READMEs, design specs): still authoritative for the why, but they get re-checked against the registry on every PR.
- Per-repo CLAUDE.md / AGENTS.md: still describes how to work in that repo, but capability claims defer to `capabilities.json`.
- Tests: still verify behavior; the registry just enumerates surface.

## Cadence

| Cadence | What happens |
|---|---|
| Per push to master in a consumer repo | Validate `capabilities.json` against schema; if OK, fire `registry-sync` dispatch into wave-foundation. |
| Per push to wave-foundation master | Re-run `aggregate.ts` against the cached snapshot of every consumer's `capabilities.json`; commit `state.json` + `STATE.md` if changed. |
| Every 6h cron | Full refresh of every consumer's `capabilities.json` from their respective master HEAD; catches anything the dispatch path missed. |
| On a major architectural change | Maintainer manually triggers `registry-aggregate.yml` via workflow_dispatch. |
