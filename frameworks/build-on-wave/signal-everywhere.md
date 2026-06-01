# Signal Everywhere — landing page spec

Spec for `wave.online/` (or `wave.online/signal-everywhere`). WSC owns the actual page; this file is the canonical copy + structure.

## Hero

> # Signal everywhere.
>
> Same stream. Same auth. Same billing. From the studio LAN to the browser tab to the AI agent paying micropayments by the second.

CTAs (touch-first, ≥44pt):
- **Start free** → sign-up flow
- **See it work** → embedded video of wave-monitor connecting to a feed in 5 seconds
- **Read the code** → repo grid (links to all 6 Layer-0 repos)

## Section 1 — the five layers (visual)

Same ASCII diagram from `protocol-plane/README.md` but rendered as an SVG:

```
┌─────────────────────────────────────────────────────────────────┐
│  Control plane  — gateway.wave.online + WSC                     │
└──┬────────┬──────────────┬──────────────┬─────────────┬─────────┘
   │        │              │              │             │
┌──▼─────┐ ┌▼────────┐ ┌──▼─────────┐ ┌──▼────────┐ ┌──▼─────────┐
│OPERATOR│ │ EDGE    │ │ BRIDGES    │ │ LOCAL     │ │ HARDWARE   │
│Desktop │ │ Workers │ │ Containers │ │ Agents    │ │ Partners   │
│Plugins │ │ MoQ     │ │ SRT/NDI/   │ │ mDNS/DAL  │ │ Certified  │
│Monitor │ │ WebRTC  │ │ Dante/OMT  │ │ discovery │ │ devices    │
└────────┘ └─────────┘ └────────────┘ └───────────┘ └────────────┘
```

Each box is touch-targetable (≥44pt) and links to its layer doc.

## Section 2 — "Here's what we built"

Three columns; each card has a 2-line description + a "View source" link to the GitHub repo + a 1-line code snippet showing the SDK usage that powers it.

```
┌─ wave-desktop ────────┐  ┌─ obs-wave-plugin ─────┐  ┌─ wave-monitor ────────┐
│ Operator console      │  │ OBS Studio plugin     │  │ Audio + video monitor │
│ Encode, receive,      │  │ WAVE as a native      │  │ Paste a feed URL,     │
│ multiview, settings.  │  │ streaming destination │  │ see signal + meters.  │
│                       │  │                       │  │                       │
│ npm i @wave-av/sdk    │  │ #include <obs-output> │  │ npm i @wave-av/sdk    │
│                       │  │                       │  │                       │
│ [ View source → ]     │  │ [ View source → ]     │  │ [ View source → ]     │
└───────────────────────┘  └───────────────────────┘  └───────────────────────┘

┌─ wave-multiviewer ────┐  ┌─ vmix-wave-integration ┐  ┌─ wave-conferencing── ┐
│ Software multiview    │  │ vMix integration       │  │ Zoom / Teams / Meet  │
│ 4x4 / 9x9 / 16x16.    │  │ TitleScripts +          │  │ ingress + virtual    │
│ Click to pin program. │  │ Web Controller + side- │  │ cam egress.          │
│                       │  │ car bridge.             │  │                      │
│ npm i @wave-av/sdk    │  │ HTTP(/v1/wave/start)   │  │ npm i @wave-av/      │
│                       │  │                         │  │ conferencing-bridge  │
│ [ View source → ]     │  │ [ View source → ]      │  │ [ View source → ]    │
└───────────────────────┘  └────────────────────────┘  └──────────────────────┘
```

## Section 3 — "Same SDK powers all of it"

A 30-second proof. One code snippet, one runtime. Replicates what wave-monitor does in ~20 lines:

```ts
import { WaveClient } from '@wave-av/sdk';

const wave = new WaveClient({ token: process.env.WAVE_TOKEN });
const feed = wave.feed('your-show-slug');

// 1. Confirm it's live
const status = await feed.status();
console.log(`live: ${status.connected}  bitrate: ${status.bitrateKbps}`);

// 2. Open a player anywhere — browser, Electron, Node, even an AI agent
const player = await feed.subscribe({ codec: 'av1' });
player.on('frame', (f) => process.stdout.write(`.`));
```

Same SDK works from:
- a browser tab
- a Node.js process
- a Bun / Deno worker
- an Electron app
- a Cloudflare Worker
- a Python script
- an AI agent loop

## Section 4 — Pricing in one sentence

> Same pricing model across every app, every protocol, every SDK, every payment rail.

| | Card (Stripe) | Crypto (x402 / Privy / Tempo) | Per-active-stream |
|---|---|---|---|
| Per-API meter | ✓ | ✓ | ✓ |
| Per-active-stream metering | ✓ | ✓ | ✓ |
| Agent micropayments | — | ✓ | ✓ |
| OB-van rate cards | ✓ | ✓ | ✓ |

→ [`pricing/`](../pricing/README.md) for the canonical model.

## Section 5 — Anti-vMix / anti-Streamyard

We are **not** competing with the apps your team already uses. We're the **billing rail and identity layer** they all share.

| | WAVE | Streamyard | vMix | OBS + N hosting |
|---|---|---|---|---|
| Use it as a product | ✓ | ✓ | ✓ | ✓ |
| Build on it as a platform | **✓** | ✗ | ✗ | partial |
| Source code open | **✓** (Layer 0 apps) | ✗ | ✗ | ✓ (OBS) |
| Unified billing across all your tools | **✓** | n/a | n/a | n/a |
| Same auth in browser + app + AI agent | **✓** | ✗ | ✗ | ✗ |
| Agent-native (x402) | **✓** | ✗ | ✗ | ✗ |

## Section 6 — Footer CTA

> **Start where it makes sense for you.**
>
> - I'm an operator → download wave-desktop
> - I'm an OBS user → install our plugin
> - I'm a developer → npm install @wave-av/sdk
> - I'm an AI agent → POST to api.wave.online with x402 + a budget cap

## Voice + tone

Per [`copywriting/voice-and-tone.md`](../copywriting/voice-and-tone.md):
- Active verbs, present tense
- One sentence per thought
- Numbers in parentheses, not adjectives
- No "best in class" / "industry leading" / "premier"
- Touch-first; if a sentence implies a click, make it a real button
