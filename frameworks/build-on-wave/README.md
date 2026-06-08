# Build on WAVE

The strategic claim: **everything WAVE customers can build, we built first.**

This framework documents the meta-dogfood positioning — a verifiable map showing each public SDK + spoke + operator app as both (a) something WAVE runs in production, and (b) something a customer or AI agent can build their own version of using only the public APIs.

## The argument in one sentence

> Streamyard / Riverside / Restream are products you have to use. WAVE is a platform you can build on. Here's what we built.

## Why this matters

Broadcasters and developers evaluating a streaming platform ask one of two questions:

| Question | What they're really asking |
|---|---|
| "Can I use this?" | Will Streamyard or Riverside or vMix do my use case faster? |
| "Can I build on this?" | Can I ship my own broadcaster, multiviewer, or workflow without rebuilding the gateway, the codecs, the auth, the billing? |

Closed platforms can only answer the first question. WAVE answers both — and we **prove** we mean it by shipping every operator-facing thing as open-source software built on the same public SDKs every customer gets.

## The credibility table

Every row below maps an existing WAVE-built app to (a) the public SDK it consumes, (b) the spoke / protocol-plane surface it consumes, and (c) the line count of customer-replicable application code. If we can build it in N lines, you can build it in N lines.

### Operator-facing apps (Layer 0)

| App | Repo | Public SDK | Protocol layer | App LOC | Replicable? |
|---|---|---|---|---|---|
| Operator Console | [wave-desktop](https://github.com/wave-av/wave-desktop) | `@wave-av/sdk` | Layer 0 | ~600 | Yes (MIT) |
| OBS Studio plugin | [obs-wave-plugin](https://github.com/wave-av/obs-wave-plugin) | (libsrt + gateway HTTP) | Layer 0 | ~400 C | Yes (GPL-2; libobs derivative) |
| vMix integration | [vmix-wave-integration](https://github.com/wave-av/vmix-wave-integration) | `@wave-av/sdk` (companion) + vMix HTTP API | Layer 0 | ~200 | Yes (MIT) |
| Multiviewer | [wave-multiviewer](https://github.com/wave-av/wave-multiviewer) | `@wave-av/sdk` | Layer 0 + Layer 1 (WebRTC SFU) | ~500 | Yes (MIT) |
| Conferencing bridge | [wave-conferencing-bridge](https://github.com/wave-av/wave-conferencing-bridge) | `@wave-av/sdk` | Layer 0 + Layer 1 | ~300 TS | Yes (MIT) |
| Audio + video monitor | [wave-monitor](https://github.com/wave-av/wave-monitor) | `@wave-av/sdk` | Layer 0 + Layer 1 | ~300 | Yes (MIT) |

### Backbone surfaces (Layers 1-4)

These run as WAVE infrastructure, but the public SDKs expose every operation they perform. A customer can build a competing edge / bridge / agent without our help.

| Surface | Repo (impl) | Public contract |
|---|---|---|
| Gateway (Layer 1, control plane) | _(internal control plane)_ | OpenAPI at `https://api.wave.online/openapi.json` + `@wave-av/sdk` |
| MoQ edge (Layer 1) | [wave-moq-edge](https://github.com/wave-av/wave-moq-edge) | IETF MoQ draft-17 (open spec) |
| WebRTC SFU edge (Layer 1) | [wave-realtime-edge](https://github.com/wave-av/wave-realtime-edge) | W3C WebRTC + LiveKit protocol |
| Protocol bridges (Layer 2) | [wave-bridge-edge](https://github.com/wave-av/wave-bridge-edge) | Per-protocol APIs (SRT / NDI / Dante / OMT / AV1 / AV2 / ffmpeg) |
| Transport library (cross-layer) | _(internal)_ | C++ API; AES67 fallback (open) + DAL wrapper (license-gated) |
| Local agent (Layer 3) | [wave-agent](https://github.com/wave-av/wave-agent) | Discovery RPC documented in `protocol-plane/` |
| Hardware certification (Layer 4) | [wave-certify](https://github.com/wave-av/wave-certify) | Open protocol-correctness battery |

### SDKs (the credibility surface itself)

| Package | Languages | Coverage |
|---|---|---|
| `@wave-av/sdk` (TypeScript / JS) | Node, Bun, Deno, browser | Every product on the OpenAPI |
| Python SDK | CPython 3.10+ | Same OpenAPI |
| Go SDK | Go 1.21+ | Same OpenAPI |
| (Rust, Swift, Kotlin) | scaffolded | Same OpenAPI |

All SDKs are **codegen'd from the canonical OpenAPI** + hand-written ergonomic wrappers. New product surface = SDK update with one PR, not five.

## "Signal everywhere" — the positioning

WAVE's tagline is **signal everywhere**: the same stream-key + the same auth + the same billing flows through:

- A browser tab (Layer 1 MoQ over WebTransport)
- A native app on a phone or studio Mac (Layer 0 wave-desktop)
- An OBS or vMix install (Layer 0 plugins)
- A Zoom / Teams / Meet meeting (Layer 0 conferencing-bridge)
- A licensed broadcast box from BirdDog / AJA / Blackmagic (Layer 4 hardware)
- An AI agent paying micropayments per stream (Layer 1 x402)
- An NDI camera on the studio LAN (Layer 3 wave-agent discovery)
- A Dante audio channel on the same LAN (Layer 2 bridge container)

Same auth, same scope, same meter, same x402 settle path — regardless of the leaf. The customer's stream-key is portable. Their billing is unified. Their integration code is the same `@wave-av/sdk` everywhere.

## Anti-positioning

We do not claim to be the **only** way to do these things. OBS, vMix, Wirecast, NDI Studio Monitor, NewTek MV-series, TVU One — these are excellent products. Many of our customers use them today and will continue.

We claim to be the **platform** these can build on, the **glue** between them, and the **billing rail** for an industry that's been stuck on per-product invoices for 30 years.

## How to use this framework

| Surface | Use this framework for |
|---|---|
| Sales call | "Show me what your team built on top of your own platform" → walk the credibility table |
| Developer-relations post | "Here's how we built wave-monitor in 300 lines on top of @wave-av/sdk — your turn" |
| Investor deck | "Open-core flywheel: every operator we recruit reads our source code and ships a custom variant" |
| Hiring brief | "We're hiring engineers who want to ship visible code in an industry that's been opaque for 30 years" |

## Live URLs

- `wave.online/build` — landing page (WSC handles the actual page; this README is the spec)
- `wave.online/sdk` — SDK index, codegen status, OpenAPI link
- `wave.online/certified` — hardware certification listing
- `downloads.wave.online/desktop` — wave-desktop installer
- `downloads.wave.online/monitor` — wave-monitor installer
- `downloads.wave.online/multiviewer` — wave-multiviewer installer
- `downloads.wave.online/obs` — OBS plugin installer

## Linked

- [`protocol-plane/`](../protocol-plane/) — the five-layer architecture this builds on
- [`pricing/`](../pricing/) — same pricing standard across every Layer 0 app + every API
- [`copywriting/`](../copywriting/) — voice and tone for the marketing pages
- wave-foundation #95 — strategic O-series roadmap
