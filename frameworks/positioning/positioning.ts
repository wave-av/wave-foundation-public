// WAVE — POSITIONING SSOT (frameworks/positioning).
//
// The canonical answer to "what is WAVE?" — the strings every surface (apex, spokes, docs, agent
// surfaces, READMEs, decks) must stay consistent with. This file owns IDENTITY + the canonical
// STRINGS + the engine/product NAMING. Sister frameworks:
//   - ../copywriting/voice-and-tone.md  → HOW we say it (voice, tone, person/agent register)
//   - ../copywriting/claims.ts          → WHAT we may assert (substantiated / inProgress / required)
// Positioning is the layer ABOVE both: the identity and narrative they express.
//
// Locked by Jake 2026-06-06 (video identity); RE-FRAMED by Jake 2026-09-02 (code yellow): WAVE is
// MEDIA INFRASTRUCTURE for the agentic internet. "Video API", "transcription API", "streaming
// platform" are capabilities INSIDE the frame, never the headline. Changes here are GOVERNED — a PR +
// the positioning gate (positioning-check.sh). Surfaces IMPORT these strings (via @wave-av/messaging)
// rather than re-type them, so the story can never drift across the estate.
//
// Truth law that binds every string below: no SOC 2 claim for WAVE itself (vendors only, attributed);
// no "first on x402"; legal entity is exactly "WAVE Online, LLC"; every count comes from
// https://gateway.wave.online/.well-known/wave-skills.json and carries its measurement date.

export const POSITIONING = {
  // ── Identity ──────────────────────────────────────────────────────────────
  // One sentence. If a surface contradicts this, the surface is wrong — not this file.
  identity:
    "WAVE is media infrastructure for the agentic internet: one call shape moves live and on-demand " +
    "media across every transport, and both kinds of user, people and agents, discover it, call it, " +
    "and pay for it per call.",
  tagline: "Media infrastructure for the agentic internet.",
  // The analogy — reuse where an analogy helps (grounded in the adk README; the org's strongest line).
  analogy:
    "Like Stripe is for payments and Resend is for email, WAVE is for media: the layer a person or an " +
    "agent calls to move it, meter it, and pay for it.",

  // ── The frame (Jake 2026-09-02). Four load-bearing facts; every headline expresses one or more. ──
  frame: {
    twoUsers:
      "The internet has two kinds of user now: people and agents. WAVE serves both on the same routes, " +
      "with the same enforcement, from one gateway.",
    oneCallShape:
      "One call shape across every transport. SRT, RIST, RTMP, WHIP and WHEP, WebRTC, MoQ, HLS, AES67, " +
      "OMT and more sit behind one API, so a caller integrates once.",
    paidPerCall:
      "Paid per call by either kind of user: x402 and MPP on Base for agents, a key and a card for " +
      "people, metered at the same gateway.",
    agentDiscoverable:
      "Discoverable by agents with no person in the loop: an MCP server, an agent card, and a skills " +
      "index under /.well-known, plus llms.txt on the apex and the gateway.",
  },

  // ── Primary vs differentiator ─────────────────────────────────────────────
  // Media infrastructure is the IDENTITY; agent-native access and payment is the DIFFERENTIATOR.
  primary:
    "media infrastructure: one call shape for live and on-demand media across every transport, for " +
    "people and for agents",
  differentiator:
    "agent-native by construction: every capability is discoverable (MCP, agent card, skills index) " +
    "and payable per call by an agent over HTTP-402 (x402) and MPP on the same route a person calls " +
    "with a key, with did:wave identity and OFAC screening on the path",
  moneyFraming:
    "The per-call payment layer, the WAVE Money Engine, powers the WAVE Wallet. It is the " +
    "DIFFERENTIATOR beneath the media infrastructure, never the headline identity. 'Agent money OS' " +
    "is a lowercase category descriptor for that engine, never the brand noun.",

  // ── Capabilities live INSIDE the frame ─────────────────────────────────────
  // Name a capability as what a caller does with WAVE, under the infrastructure identity. Never let a
  // capability become the headline ("WAVE is a video API" is forbidden below).
  capabilities: {
    rule:
      "Video API, transcription API, live streaming, captions, clips, and dispatch are capabilities " +
      "inside the frame. Lead with the infrastructure; list the capability beneath it.",
    examples: [
      "live and on-demand video across every transport",
      "transcription, captions, and dubbing",
      "clips, chapters, search, and sentiment",
      "voice and phone",
      "routing decisions (dispatch)",
    ],
  },

  // ── The three engines + the product ────────────────────────────────────────
  // THE RULE for "Engine" billing: a pillar is an engine when it has (1) a live product surface,
  // (2) an apex page, and (3) a priced capability — a meter family at the gateway. Media, Money, and
  // Dispatch clear all three (dispatch: wave_dispatch_decisions, $0.0001/decision over x402). Trust
  // clears the first two and has no meter, so it is a PILLAR beside the engines (see `trust` below).
  // Agents are an AUDIENCE lens (see `audiences`), never a pillar or an engine.
  engines: {
    media: {
      name: "WAVE Media Engine",
      what:
        "moves the media: video, audio, and captions, in and out, file and stream, local and global, " +
        "across every transport behind one call shape",
      surfaces: ["https://wave.online/media-engine", "https://engine.wave.online"],
    },
    money: {
      name: "WAVE Money Engine",
      what:
        "gets both kinds of user paid on one rail: x402 and MPP on Base for agents, cards for people, " +
        "with did:wave identity, OFAC screening, and metering on the path",
      surfaces: ["https://wave.online/money-engine", "https://money-engine.wave.online"],
    },
    dispatch: {
      name: "WAVE Dispatch Engine",
      what:
        "chooses the path: which tier runs the work, at what cost, under whose keys. It meters the " +
        "decision, never the inference; keys, prompts, and models stay on the caller's infrastructure",
      surfaces: ["https://wave.online/dispatch-engine", "https://dispatch.wave.online"],
    },
  },
  // Trust — the pillar beside the engines. The public compliance posture plus every legal commitment,
  // readable by a person on the apex and by an agent in one request (RFC 9116 security.txt).
  trust: {
    name: "WAVE Trust",
    what:
      "the public compliance posture (GDPR/CCPA aligned with a signed DPA available; HIPAA-ready under a " +
      "signed BAA; EU AI Act Article 26 record-keeping) and every legal commitment, readable by a person " +
      "at wave.online/trust and by an agent in one request at trust.wave.online. No SOC 2 claim for WAVE " +
      "itself; vendors (Cloudflare, Supabase, Stripe) are attributed, never borrowed",
    surfaces: ["https://wave.online/trust", "https://trust.wave.online"],
  },
  product: {
    name: "WAVE Wallet",
    what:
      "the product face of the Money Engine: a 4-party wallet network (creator + creator's agent ⟷ " +
      "viewer + viewer's agent), so micropayments for media are native on one rail",
    surface: "https://wallet.wave.online",
    status: "planned" as const, // NOT a public product yet — see ../copywriting/claims.ts. Do not assert as available.
  },

  // ── Agent discovery — the live surfaces an agent reads with no person in the loop ──────────
  // Counts are MEASURED from the skills index and dated; re-measure before citing (never round up).
  discovery: {
    mcp: "https://mcp.wave.online/mcp",
    agentCard: "https://gateway.wave.online/.well-known/agent-card.json",
    skillsIndex: "https://gateway.wave.online/.well-known/wave-skills.json",
    scopes: "https://gateway.wave.online/.well-known/wave-scopes.json",
    x402: "https://gateway.wave.online/.well-known/x402",
    llmsTxt: ["https://wave.online/llms.txt", "https://gateway.wave.online/llms.txt"],
    counts: {
      skills: 178,
      x402Priced: 175,
      settlement: "USDC; 174 settle on Base, 1 on Tempo",
      measured: "2026-09-02",
      source: "https://gateway.wave.online/.well-known/wave-skills.json",
    },
  },

  // ── Audiences — always BOTH, never one at the other's expense ───────────────
  audiences: [
    "the people who make media and build with a key",
    "the agents that discover, call, and pay for it with a credential",
  ],
  // Per-audience lines: the same frame, spoken to one reader. Each leads with the infrastructure.
  audienceLines: {
    people:
      "Integrate once and move live and on-demand media across every transport with one key. The " +
      "same route your users call, their agents can call and pay for.",
    agents:
      "Discover WAVE over MCP, read the skills index, and pay per call over x402 or MPP on Base. No " +
      "account, no person in the loop, the same routes and enforcement a person gets.",
    enterprise:
      "One gateway enforces authentication, scope, entitlement, and metering for every caller, " +
      "person or agent. The compliance posture is public and machine-readable.",
    investors:
      "Media infrastructure for an internet with two kinds of user. Three engines under one call " +
      "shape, paid per call by people and by agents, discoverable by agents without a sales motion.",
  },

  // ── Elevator pitches — pick by length budget ────────────────────────────────
  pitches: {
    oneLiner:
      "One call shape for live and on-demand media across every transport, paid per call by people " +
      "and by agents.",
    short:
      "WAVE is media infrastructure for the agentic internet. One call shape moves live and on-demand " +
      "media across every transport. A person calls it with a key; an agent discovers it over MCP and " +
      "pays per call over x402 or MPP on Base. Same routes, same enforcement, one gateway metering both.",
    paragraph:
      "WAVE is media infrastructure for the agentic internet. The internet now has two kinds of user, " +
      "people and agents, and WAVE serves both on the same routes. One call shape moves live and " +
      "on-demand media across every transport: SRT, RIST, RTMP, WHIP and WHEP, WebRTC, MoQ, HLS, AES67, " +
      "OMT and more, through one contract (the WAVE Media Engine). Every capability is paid per call by " +
      "either kind of user: x402 and MPP on Base for agents, a key and a card for people, with did:wave " +
      "identity and OFAC screening on the payment path (the WAVE Money Engine). A third engine decides " +
      "which tier runs each unit of work and meters the decision, never the inference (the WAVE Dispatch " +
      "Engine). Agents find all of it with no person in the loop: an MCP server, an agent card, and a " +
      "skills index under /.well-known. Video, transcription, captions, clips, and streaming are " +
      "capabilities inside that frame, not the frame itself.",
  },

  // ── FORBIDDEN positioning — the gate flags these in user-facing marketing copy ──
  // (Distinct from copywriting's voice gate and claims.ts. This guards the IDENTITY.)
  forbidden: [
    {
      pattern: /\bThe Agent Money OS\b/i,
      why: "Demoted (#627 over-rotation). WAVE IS media infrastructure; 'agent money OS' is a lowercase " +
        "engine descriptor, never the headline brand/tagline. Use the canonical tagline or 'WAVE Money Engine'.",
    },
    {
      pattern: /\bMoney OS\b/,
      why: "Not the brand identity. Use 'WAVE Money Engine' for the engine, 'WAVE Wallet' for the product.",
    },
    {
      pattern: /\bvideo infrastructure for the agentic internet\b/i,
      why: "Superseded 2026-09-02. Media is the identity; video is a capability inside it. Use " +
        "POSITIONING.tagline: 'Media infrastructure for the agentic internet.'",
    },
    {
      pattern: /\bWAVE is (?:a |an |the )?(?:video|transcription|streaming|captions?) (?:API|platform|service)\b/i,
      why: "A capability is not the identity. Lead with 'media infrastructure for the agentic internet'; " +
        "name the capability beneath it (see POSITIONING.capabilities.rule).",
    },
  ],
} as const;

export type Positioning = typeof POSITIONING;
