# Platform State

> _Seeded; not yet aggregator-generated. Phase D backfills `capabilities.json`
> for every wave-av repo, then `scripts/aggregate.ts` regenerates this file._
>
> Do NOT hand-edit once the aggregator is wired — modify each repo's
> `capabilities.json` and re-run the aggregator.

## Status

| | |
|---|---|
| Schema version | `1` |
| Repos with `capabilities.json` | 0 of 38 (backfill pending) |
| Last full aggregator run | _never — Phase D not started_ |
| Aggregator workflow | `.github/workflows/registry-aggregate.yml` (wired Phase B) |

## How to read this once it's live

- **Layer 0..4 tables** group repos by protocol-plane layer (see [protocol-plane README](../protocol-plane/README.md)).
- **Non-plane** holds SDKs, marketing surfaces, agent tools, governance scaffolds.
- **Cross-references** table shows reverse dependencies — "who consumes repo X?" — generated from each repo's `consumes.waveProducts`.

## Adoption status (manual, until Phase D)

Layer 0 — Operator (target: 100% backfilled in Phase D):
- [ ] wave-desktop
- [ ] wave-monitor
- [ ] wave-multiviewer
- [ ] obs-wave-plugin
- [ ] vmix-wave-integration
- [ ] wave-conferencing-bridge

Layer 1 — Edge:
- [ ] wave-realtime-edge
- [ ] wave-gateway
- [ ] wave-clip-engine
- [ ] wave-bridge-edge

Layer 2 — Bridges:
- [ ] wave-transports
- [ ] wave-ndi-edge
- [ ] wave-dante-edge
- [ ] wave-omt-edge
- [ ] wave-moq-edge

Layer 3 — Local:
- [ ] wave-agent
- [ ] wave-flash
- [ ] wave-profiles

Layer 4 — Hardware:
- [ ] wave-certify
- [ ] wave-hardware-designs

Non-plane:
- [ ] sdks, sdk, sdk-python, api-spec, adk, mcp-server, cli, workflow-sdk, examples
- [ ] companion-module-wave, wave-modules
- [ ] dispatch-edge, wave-dispatch
- [ ] wave-foundation, wave-foundation-public, .github
- [ ] wave-www, wave-developer, wave-docs-www, wave-agents-www, wave-web-www
- [ ] wave-surfer, wave-surfer-connect
- [ ] create-wave-app

(Total: 38 repos. List sourced from `gh repo list wave-av` at PR-open time.)
