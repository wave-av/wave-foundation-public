# The WAVE story

_The long-form narrative — the source for the public `/story` surface (#140) and the spine for decks,
about pages, and investor material. Everything here is grounded in `positioning.ts` and stays inside
the substantiated-claims register (`../copywriting/claims.ts`)._

## The shift

The internet is getting a second kind of user. Alongside the people who watch, create, and broadcast,
there are now autonomous agents that discover, negotiate, and pay for services with no human in the
loop. Most infrastructure was built for one of those users — not both. Video is the hardest case:
real-time, expensive to move, fragmented across a dozen incompatible transports, and almost never
designed for a machine to pay for directly.

## What WAVE is

**WAVE is video infrastructure for the agentic internet** — an open protocol and one API for live and
on-demand video, built for the people who make it and the agents that pay for it. You integrate once;
WAVE moves the video across every transport, and the same surface a person calls with a key, an agent
can call — and pay for — over HTTP-402.

Two engines sit under that one API.

### The WAVE Media Engine — move the video

The hard parts of moving audio and video are solved once, in an open core, so every transport is a thin
adapter on top: a single media clock, a uniform duplex adapter interface, integrity, sync, reliability,
and metering. Add a protocol — SRT, RIST, AES67, OMT, MoQ, HLS, WebRTC — and it inherits all of it. No
rebuilding the hard parts per format. Real adapters ship on it today; the roadmap is labeled honestly,
live versus building versus planned.

### The WAVE Money Engine — get everyone paid

Payment, identity, and compliance are native to the same surface, not bolted on. WAVE runs a public
x402 facilitator, live on Base mainnet: an agent proves its identity with a `did:wave` credential,
settles on-chain, and is screened against sanctions on the way through — the same routes a person hits
with a bearer key. This is the differentiator, not the headline: the payment layer is what lets the
video infrastructure serve agents as first-class customers.

### The WAVE Wallet — the network the engines make possible

The Money Engine's product face is the **WAVE Wallet**: a wallet every party holds — the creator and
their agent, the viewer and theirs. When all four sides transact on one rail, micropayments for video
become native and cheap: a viewer's agent can pay a few cents for a clip, a creator's agent can get
paid the instant it delivers. That four-party symmetry is the point. _(The Wallet is being built; it is
not yet a public product — and we don't claim it as one until it is.)_

## Why it's different

- **Open where it earns trust, metered where it earns revenue.** The engine core is open; commercial
  adapters and edge services build on top.
- **One surface for people and agents.** Not a human product with an agent add-on, and not an agent
  API with a marketing site — the same routes, the same enforcement, two registers of the same story.
- **Truthful by construction.** Every public claim is backed by shipped code or a real document; the
  roadmap is labeled, not implied. Being the honest, compliant one is a feature.

## Who it's for

The people who make video — creators, streamers, broadcasters, video-infrastructure teams — and the
agents that discover, deliver, and pay for it. WAVE is the layer underneath both.
