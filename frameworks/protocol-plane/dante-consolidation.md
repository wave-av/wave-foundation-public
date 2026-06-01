# Dante Consolidation

The Dante integration in the [Protocol Plane](README.md) Bridges layer is **NOT in research mode** — it is at 95% completion across multiple repos. This doc consolidates the existing surface and maps the remaining 5% of extraction + deploy work. Tracks task #137.

## License status

**Audinate Dante SDK license: OWNED.** Source: `wave-transports/CMakeLists.txt` (`# TODO(wave-transports): add_subdirectory(dante) — P4 (Audinate SDK — license OWNED; assets in WSC)`).

Task #141 (Audinate partner outreach) reframes from "required for Dante shipment" to "expand scope (service-provider terms for higher endpoint count)" — the baseline license is already in hand.

## What's already built (inventory)

### wave-surfer-connect (WSC) — 95% complete

Per [DANTE_HANDOFF_SUMMARY.md](https://github.com/wave-av/wave-foundation/blob/master/staging/_external/wsc-docs/DANTE_HANDOFF_SUMMARY.md):

**15 React components** at `src/components/customer/protocols/dante/`:
- DanteControlCenter (main, 11 tabs)
- DanteRoutingMatrix (visual audio routing grid)
- DanteDeviceManager (discovery + management)
- DanteClockVisualizer (PTP hierarchy display)
- DanteAudioMonitoring (real-time meters)
- DanteNetworkHealth (perf monitoring)
- DanteProtocolBridge (protocol conversion)
- + 8 more

**10 backend services** at `src/services/protocols/dante/`:
- DanteService.ts (main orchestrator)
- RealDanteService.ts (production impl)
- DanteDiscovery.ts (device discovery)
- DanteRouting.ts (audio routing)
- DanteMonitoring.ts (perf monitoring)
- DanteWebSocket.ts (real-time updates)
- + 4 more supporting

**Full REST + WS API**:
```
GET    /api/v1/dante/routing               # List routes
POST   /api/v1/dante/routing               # Create route
DELETE /api/v1/dante/routing/[id]          # Delete route
GET    /api/v1/dante/nodes/[id]/devices    # List devices
WS     /api/v1/dante/ws                    # Real-time updates
```

**11 DB tables** (Supabase): `dante_devices`, `dante_routing_subscriptions`, `dante_monitoring_data`, `dante_alerts`, `dante_clock_status`, `wave_nodes`, + 5 more.

**Auth**: JWT on all endpoints (already wired to gateway scope claims).
**Tests**: comprehensive suite incl. integration + performance.
**Mocks**: full mock impl mirroring real API surface for dev.

### wave-transports — kernel layer hook

`CMakeLists.txt` reserves `dante/` subdirectory. License-owned. Native bindings TBD.

### wave-av/agents — Python controller

`tools/production/dante_audio_controller.py` (24KB) — DANTE protocol implementation, open-source variant. Used by the agent tooling for AI-driven Dante routing.

### wave-modules — module catalog

`wave-dante-in` module in `MODULE-CATALOG.md` — Dante audio over IP receive, GbE transport. Sits next to `wave-aes67-in` (AES67 fallback path).

### wave-dante-edge — already scaffolded

Repo exists at `wave-av/wave-dante-edge` (live as `dante.wave.online`). Scaffolded with the same chassis pattern as the other edge spokes.

### downloads.wave.online — node binaries

Live URL serving signed Wave Node binaries (Windows/macOS/Linux/Docker) per the existing implementation.

## What's left — the 5%

Per the WSC handoff doc:

| Item | Owner | Status |
|---|---|---|
| Audinate SDK extraction → wave-transports `dante/` subdirectory | engineering | not started |
| Real hardware testing (we have mocks) | engineering + ops | not started |
| Wave Node binary code signing | ops | not started |
| Production deployment (currently in staging) | ops | not started |
| wave-bridge-edge `dante/` container — uses extracted SDK | engineering | empty scaffold ready (PR #2) |

## Topology — confirmed

```
┌─────────────────────────────────────────────────────────────┐
│  studio LAN                                                  │
│  ┌─────────────┐  Dante AOIP (L2 multicast, PTP-synced)     │
│  │  Yamaha     │ ────────────┐                              │
│  │  CL5 mixer  │             │                              │
│  └─────────────┘             │                              │
│  ┌─────────────┐             ▼                              │
│  │  Shure mics │  ┌─────────────────────────────────┐       │
│  │             │  │  Wave Node (downloads.wave.online)│      │
│  └─────────────┘  │  + DanteDiscovery + Routing      │      │
│                   └──────────────┬───────────────────┘      │
└──────────────────────────────────│──────────────────────────┘
                                   │ encrypted unicast
                                   ▼
            ┌──────────────────────────────────────────────┐
            │  WSC backend (api.wave.online)               │
            │  RealDanteService + DanteWebSocket + 11 DBs  │
            │  Customer UI: DanteControlCenter             │
            └──────────────────────────────────────────────┘
                                   │
                                   ▼
            ┌──────────────────────────────────────────────┐
            │  wave-bridge-edge containers/dante (cloud)   │
            │  DAL endpoint → MoQ audio track conversion   │
            │  (Wave-1 extraction; SDK license OWNED)      │
            └──────────────────────────────────────────────┘
```

## What changes for the Protocol Plane framing

1. **Dante is not the long pole** — it's actually further along than NDI (which still needs license clearance from Vizrt for server-side container redistribution).
2. **The wave-bridge-edge `dante/` container is the cloud-side cherry on top**, not the foundation — the foundation is the WSC + Wave Node deployment that already works in staging.
3. **AES67 fallback path stays relevant** for non-licensed partners, but is no longer the primary plan.
4. **Audinate partner relationship (#141)** still useful — but for SCALE (more endpoints, service-provider terms), not for baseline licensing.

## Open questions (now narrower)

1. Does the existing WSC RealDanteService.ts call the Audinate SDK directly, or is it a higher-level wrapper that the wave-transports kernel layer will replace? (Need to read RealDanteService.ts to confirm.)
2. What's the production deploy gating? CF token? Code signing key? Audinate hardware testing partner?
3. The Python controller in wave-av/agents — is it AES67-based (open) or DAL-based (licensed)? If AES67, it's the fallback rail; if DAL, it duplicates the WSC RealDanteService.

## Next actions

1. Read `wave-surfer-connect/src/services/protocols/dante/RealDanteService.ts` to confirm SDK integration point
2. Update `wave-bridge-edge/containers/dante/` from license-blocked scaffold to "Audinate-owned" stub that calls into wave-transports kernel layer
3. Coordinate with WSC team on production-deploy gating (code signing + hardware testing)
4. Reframe task #141: Audinate scale-tier engagement, not baseline licensing
5. Reframe task #137: consolidation + 5% finish, not research

## Linked

- [DANTE_HANDOFF_SUMMARY.md](https://github.com/wave-av/wave-foundation/blob/master/staging/_external/wsc-docs/DANTE_HANDOFF_SUMMARY.md) — original WSC handoff doc (95% complete claim verified)
- [DANTE_QUICK_REFERENCE.md](https://github.com/wave-av/wave-foundation/blob/master/staging/_external/wsc-docs/DANTE_QUICK_REFERENCE.md) — API + URLs + commands
- [wave-transports/CMakeLists.txt](https://github.com/wave-av/wave-transports/blob/master/CMakeLists.txt) — kernel-layer hook (license OWNED confirmation)
- [Protocol Plane](README.md) — where this fits
