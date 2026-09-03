# The WAVE story

_The long-form narrative: the source for the public `/story` surface and the spine for decks, about
pages, and investor material. Everything here is grounded in `positioning.ts` and stays inside the
substantiated-claims register (`../copywriting/claims.ts`). Re-framed 2026-09-02: WAVE is media
infrastructure for the agentic internet; video, transcription, and streaming are capabilities inside
that frame._

## The shift

The internet has a second kind of user. Alongside the people who watch, create, and broadcast, there
are now autonomous agents that discover, negotiate, and pay for services with no person in the loop.
Most infrastructure was built for one of those users, not both. Media is the hardest case: real-time,
expensive to move, split across a dozen incompatible transports, and almost never designed for a
machine to find and pay for directly.

## What WAVE is

**WAVE is media infrastructure for the agentic internet.** One call shape moves live and on-demand
media across every transport, and both kinds of user, people and agents, discover it, call it, and pay
for it per call. A person integrates once with a key. An agent reads the skills index, calls the same
route, and settles over HTTP-402. Same routes, same enforcement, one gateway metering both.

Four facts carry the frame:

1. **Two kinds of user.** People and agents, served on the same routes from one gateway.
2. **One call shape across every transport.** SRT, RIST, RTMP, WHIP and WHEP, WebRTC, MoQ, HLS, AES67,
   OMT and more sit behind one API. Add a transport and the caller changes nothing.
3. **Paid per call by either kind of user.** x402 and MPP on Base for agents, a key and a card for
   people, metered at the same gateway.
4. **Discoverable by agents.** An MCP server, an agent card, and a skills index under `/.well-known`,
   plus `llms.txt` on the apex and the gateway. As of 2026-09-02 the skills index lists 178 skills,
   175 of them priced over x402 in USDC (174 settle on Base, 1 on Tempo).

Three engines sit under that one call shape. One carries the media, one clears the payment, one chooses
the path. A pillar stands beside them: a trust posture anyone, person or agent, can read without asking.

### The WAVE Media Engine: move the media

The hard parts of moving audio, video, and captions are solved once, in an open core, so every
transport is a thin adapter on top: a single media clock, a uniform duplex adapter interface,
integrity, sync, reliability, and metering. Add a protocol and it inherits all of it. No rebuilding the
hard parts per format. Real adapters ship on it today; each capability carries its status: live,
building, or planned.

### The WAVE Money Engine: get both kinds of user paid

Payment, identity, and compliance are native to the same surface, not bolted on. WAVE runs a public
x402 facilitator, live on Base mainnet: an agent proves its identity with a `did:wave` credential,
settles on-chain, and is screened against sanctions on the way through. A person hits the same routes
with a bearer key and a card. This is the differentiator, not the headline: per-call payment is what
lets media infrastructure serve agents as first-class customers.

### The WAVE Dispatch Engine: choose the path

Once media can move and value can settle, something still has to decide what compute each request
needs. The Dispatch Engine classifies a prompt at the edge and returns a routing decision in
milliseconds: which tier runs the work, at what cost, under whose keys. WAVE bills the decision,
$0.0001 over x402 or a card subscription, and never the inference. Keys, prompts, and models stay on
the caller's infrastructure; that wall is the product. Like every WAVE capability, each decision is
callable with a key and payable by an agent over HTTP-402 on the same route, and the service runs in
production at `dispatch.wave.online`. It is an engine, not an AI feature: it does not replace models,
it decides which one earns the turn.

### The WAVE Wallet: the network the engines make possible

The Money Engine's product face is the **WAVE Wallet**: a wallet every party holds, the creator and
their agent, the viewer and theirs. When all four sides transact on one rail, micropayments for media
become native and cheap: a viewer's agent can pay a few cents for a clip, a creator's agent can get
paid the instant it delivers. That four-party symmetry is the point. _(The Wallet is being built; it is
not yet a public product.)_

### Trust: the pillar beside the engines

Trust is a pillar, not an engine: it has a live surface and an apex page but no meter, and nothing is
sold on it. Every request, from a person or an agent, passes one edge gateway that enforces
authentication, scope, entitlement, and metering, and returns 403 when an account is not entitled. The
posture is public. The trust center (`wave.online/trust`) states the compliance position: GDPR/CCPA
aligned with a signed DPA available, HIPAA-ready under a signed BAA, EU AI Act Article 26
record-keeping, and it lists every subprocessor. The same posture is machine-readable at
`trust.wave.online`, where the security contact and disclosure policy ship as an RFC 9116
`security.txt` that a person or an agent reads with one request. No SOC 2 claim for WAVE itself;
vendors (Cloudflare, Supabase, Stripe) are attributed, never borrowed. The legal entity behind every
commitment is WAVE Online, LLC.

**Agents are the audience lens, not a pillar.** Every engine and the trust pillar serve both audiences
on the same routes; `agents.wave.online` is the register of the same story written for the second user.

## Capabilities inside the frame

Video API, transcription API, live streaming, captions, clips, chapters, search, voice, phone, and
routing decisions are what a caller does with WAVE. Each is a capability inside the frame, listed
beneath the infrastructure identity and never promoted to the headline. The skills index is the
authoritative list; a surface that needs a count reads it and dates the number.

## Why it's different

- **Open where it earns trust, metered where it earns revenue.** The engine core is open; commercial
  adapters and edge services build on top.
- **One surface for people and agents.** Not a person-facing product with an agent add-on, and not an
  agent API with a marketing site: the same routes, the same enforcement, three engines under one call
  shape, two registers of the same story.
- **Labeled roadmap.** Every public capability carries its status: live, building, or planned. NDI,
  Dante, and ST 2110 are roadmap. The Wallet is being built.

## Who it's for

The people who make media (creators, streamers, broadcasters, media-infrastructure teams) and the
agents that discover, call, and pay for it. WAVE is the layer underneath both.
