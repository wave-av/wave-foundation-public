# Protocol Plane

The broadcast/studio-grade protocols (NDI, Dante, SRT, OMT, MoQ) WAVE speaks fluently. Distinct from [realtime-media](../realtime-media/README.md) which covers LiveKit/MUX for browser-first interactive + 1-many delivery.

## Why this exists separately

LiveKit + MUX are HTTP/WebRTC-native — they assume the consumer is a browser or app, and the producer is a webcam/mic. The broadcast world isn't that: SDI capture cards, Dante audio over Layer-2 LAN, NDI cameras discovered via mDNS, hardware encoders speaking SRT, OB van rack-stacks running OMT. **These protocols can't run in V8 isolates** — they need native binaries (libsrt, NDI Library, Dante Application Library) and often LAN-local discovery that doesn't traverse the public internet.

WAVE positions as **the signal everywhere** — same auth, same scope, same meter, same x402 settlement — regardless of whether the consumer is a browser tab, an AI agent, a studio Mac, or a certified OB van.

## Five-layer architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Control plane  — gateway.wave.online + WSC                      │
│  (auth/scope/meter/discovery, mainnet x402 settlement)           │
└──┬────────┬──────────────┬──────────────┬─────────────┬─────────┘
   │        │              │              │             │
┌──▼─────┐ ┌▼────────┐ ┌──▼─────────┐ ┌──▼────────┐ ┌──▼─────────┐
│OPERATOR│ │  EDGE   │ │  BRIDGES   │ │   LOCAL   │ │  HARDWARE  │
│(Desktop│ │(Workers)│ │(Containers)│ │  (Agents) │ │  (Partners)│
│+Apps)  │ │         │ │            │ │           │ │            │
└────────┘ └─────────┘ └────────────┘ └───────────┘ └────────────┘
   │           │              │              │             │
   └───────────┴──────────────┴──────────────┴─────────────┘
                       │
              ONE token grants access
              across all five layers
```

### Layer 0 — Operator (desktop apps + plugins)

The last-mile + first-mile: software that runs on the broadcast engineer's
own machine. Closes the gap between their LAN (cameras, DAWs, switchers,
conferencing apps) and the WAVE gateway. Every signal on their network
routes through WAVE automatically once Layer 0 is installed.

| Surface | Repo | License | Role |
|---|---|---|---|
| Operator Console (umbrella app) | [wave-desktop](https://github.com/wave-av/wave-desktop) | MIT | Encoders + Receivers + Multiview + Settings, one app |
| OBS Studio plugin | [obs-wave-plugin](https://github.com/wave-av/obs-wave-plugin) | GPL-2 (libobs derivative) | WAVE as a native OBS streaming destination (direct SRT push) |
| vMix integration | [vmix-wave-integration](https://github.com/wave-av/vmix-wave-integration) | MIT | Title presets + Web Controller + companion sidecar bridging vMix HTTP API ↔ wave-desktop |
| Multiview receiver | [wave-multiviewer](https://github.com/wave-av/wave-multiviewer) | MIT | 4×4 / 9×9 / 16×16 grid + optional WebRTC push of composite to cloud directors |
| Conferencing bridge | [wave-conferencing-bridge](https://github.com/wave-av/wave-conferencing-bridge) | MIT | Types + per-platform driver design docs for Zoom/Teams/Meet virtual cam + RTMP ingress |
| Audio + video monitor | [wave-monitor](https://github.com/wave-av/wave-monitor) | MIT | NDI Studio Monitor analog — paste a feed URL, see signal + meters |

All six are **open-source by design** (the "Build on WAVE" credibility argument — see [`../build-on-wave/README.md`](../build-on-wave/README.md)). License-gated binaries (DAL, NDI Library) are fetched at install time per the operator's own credentials; never vendored.

### Layer 1 — Edge (CF Workers)

| Protocol | Why Workers | Status |
|---|---|---|
| MoQ | WebTransport is HTTP/3 native; relays are JS | wave-moq-edge live, Phase-B XL real impl pending |
| WebRTC SFU | JS LiveKit room mgmt + ICE | wave-realtime-edge (TBD) |
| http→x402 | pure JS auth/scope/meter | wave-gateway live |
| Discovery | KV-backed registry of cross-layer endpoints | wave-gateway live |

### Layer 2 — Bridges (CF Containers — GA 2026-04-13)

| Protocol | Why Containers | Status |
|---|---|---|
| SRT | libsrt is C/C++, no Worker fit | wave-bridge-edge (planned) |
| NDI | NDI Library is Newtek binary; needs licensing | wave-bridge-edge (planned, NDI license TBD) |
| Dante | DAL is Audinate-licensed binary | wave-bridge-edge (planned, Audinate partner TBD) |
| OMT | reference impl C-based; possibly WASM-able later | wave-bridge-edge (planned) |
| ffmpeg transcode | massive binary, full Linux env | wave-bridge-edge (planned) |

CF Containers attributes that make this work:
- **Active-CPU pricing** — bridges only burn cost while protocol traffic flowing
- **Docker Hub OCI** — any image, including proprietary licensed binaries
- **Outbound Workers** — Container ↔ Worker bindings via hostname (so a bridge container can call back into the gateway for scope checks)
- **SSH-into-live** — debug a stuck stream in prod without rebuild
- **Thousands concurrent** — per-customer bridge instance possible at scale

### Layer 3 — Local Agent (wave-agent daemon)

The discovery problem: NDI and Dante use **mDNS / Layer-2 multicast / link-local addressing** that does NOT traverse the public internet. A camera in a studio in Brooklyn cannot be discovered from `gateway.wave.online` without something on the local network bridging it.

Solution: `wave-agent` — a daemon that:
1. Runs on a workstation in the same LAN as the cameras/sources
2. Authenticates to the WAVE gateway with a device-bound token
3. Discovers local NDI/Dante sources via mDNS continuously
4. Registers them in the gateway with a stable address: `ndi://customer.wave.online/<source-id>`
5. Bridges outbound: when a Container or Edge route wants to consume the source, the agent forwards the L2 traffic via the gateway's encrypted tunnel
6. Bridges inbound: when a cloud stream needs to land as a local NDI/Dante source, the agent re-emits it on the LAN

Tech direction:
- Go core (cross-platform, single binary, mDNS libs mature)
- Optional UI via Wails (Go+webview, tiny, native feel) or Tauri (Rust+webview, even tinier)
- macOS preferred install: brew tap + LaunchAgent + tray icon
- Win install: MSI + Service + tray
- Linux install: deb/rpm + systemd unit
- Auth: gateway-issued device-binding token (rotating 24h, stored in keychain/credstore)

### Layer 4 — Hardware (WAVE Certified partners)

We are **NOT building hardware**. We are building the integration story:

| Category | Example partners | Integration |
|---|---|---|
| NDI cameras + encoders | BirdDog, PTZOptics, Newtek | "WAVE Certified" badge; provided SDK adapter |
| SDI capture / decoder | AJA HELO, Blackmagic Decklink, Magewell | dropin SDK; CLI config that registers device with WAVE on first boot |
| Dante audio I/O | Audinate-licensed devices | requires Audinate partner relationship first |
| OB van + truck systems | OB-van integrators (Bexel, NEP, Game Creek) | reference install kit + certification curriculum |
| Audio mixing + telos | Telos Alliance, Wheatstone | OMT-bridge container per console |

**Certification:** ship a `wave-certify` CLI that runs a protocol-correctness battery (NDI frame integrity, Dante clock sync, SRT round-trip latency, MoQ track parity). Partner gets a signed certification artifact + public listing on `wave.online/certified`.

## Cross-layer identity

Same token, same scope rules, same x402 settle path — regardless of layer:

| Customer pattern | Layer used | Token form |
|---|---|---|
| Browser tab watching a stream | Edge (MoQ via WebTransport) | session cookie → gateway-issued JWT |
| Mobile app pulling RTMP | Edge (RTMP-WebTransport bridge) | OIDC token → gateway-issued scoped JWT |
| Studio Mac with cameras | Local Agent | device-binding token (24h rotating) → relays gateway JWT for routing |
| Hardware NDI camera | Edge (bridged via local Agent) | partner SDK ships with device-token bootstrap |
| OB van full rack | Hardware tier | install kit injects device-tokens at provisioning |
| AI agent orchestrating | Edge (http+x402) | x402 micropayment + scope JWT |

One identity model. One scope rules engine. One billing line.

## Protocol-by-protocol status

| Protocol | Open spec? | License path | Status (2026-05-30) |
|---|---|---|---|
| **MoQ** | IETF draft-17, open | None | Worker live; XL real impl Q3 2026 |
| **SRT** | open + libsrt BSD | None | wave-bridge-edge spike planned |
| **NDI** | Newtek/Vizrt | SDK redistribution check pending | Container scaffold; license blocking |
| **Dante** | Audinate proprietary | DAL per-endpoint license + partner relationship | Research mode; long pole |
| **OMT** | open spec, ref impl | None | wave-bridge-edge planned |
| **WebRTC SFU** | open W3C | None | Edge + LiveKit (see [realtime-media](../realtime-media/README.md)) |

## Cost model envelope

| Layer | Cost driver | Per-customer-month ballpark |
|---|---|---|
| Edge | Worker invocations + KV/R2 storage + egress | $0.50–$5 |
| Bridges | Container vCPU-sec + Container egress | $5–$50 (heavy active-stream tenants higher) |
| Local Agent | $0 cost to WAVE (runs on customer hardware) | — |
| Hardware certification | partner-program revenue (not cost) | net positive |

The bridges layer is the expensive one. Active-CPU pricing means **idle tenants don't burn cost**, which is the key economic unlock.

## What NOT to do

- ❌ Try to ship a Dante container without Audinate partner — license violation
- ❌ Run NDI Library binary in a customer's browser (it's a server-side binary)
- ❌ Bridge NDI via the public internet without an agent in the source LAN — mDNS won't work
- ❌ Hard-code device tokens — always provision via the agent's device-binding flow
- ❌ Skip x402 metering at the bridges layer — bridge traffic is the largest cost driver

## Linked

- [O-series roadmap (wave-foundation #95)](https://github.com/wave-av/wave-foundation/issues/95) — O5 Bridge becomes the first commercial product on the Bridges layer
- [realtime-media framework](../realtime-media/README.md) — LiveKit/MUX for browser-first delivery (complementary, not redundant)
- [WAVE Edge Plane roadmap (wave-foundation #95)](https://github.com/wave-av/wave-foundation/issues/95) — strategic O-series
- [wave-foundation #96](https://github.com/wave-av/wave-foundation/issues/96) — Vercel cost migration
