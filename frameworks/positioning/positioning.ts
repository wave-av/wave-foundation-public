// WAVE — POSITIONING SSOT (frameworks/positioning).
//
// The canonical answer to "what is WAVE?" — the strings every surface (apex, spokes, docs, agent
// surfaces, READMEs, decks) must stay consistent with. This file owns IDENTITY + the canonical
// STRINGS + the engine/product NAMING. Sister frameworks:
//   - ../copywriting/voice-and-tone.md  → HOW we say it (voice, tone, human/agent register)
//   - ../copywriting/claims.ts          → WHAT we may assert (substantiated / inProgress / required)
// Positioning is the layer ABOVE both: the identity and narrative they express.
//
// Locked by Jake 2026-06-06. Changes here are GOVERNED — a PR + the positioning gate
// (positioning-check.sh). Surfaces should IMPORT these strings (via @wave-av/messaging, task #138)
// rather than re-type them, so the story can never drift across the estate.

export const POSITIONING = {
  // ── Identity ──────────────────────────────────────────────────────────────
  // One sentence. If a surface contradicts this, the surface is wrong — not this file.
  identity:
    "WAVE is video infrastructure for the agentic internet — an open protocol and one API for live " +
    "and on-demand video, built for the people who make it and the agents that pay for it.",
  tagline: "Video infrastructure for the agentic internet.",
  // The analogy — reuse where an analogy helps (grounded in the adk README; the org's strongest line).
  analogy: "Like Stripe is for payments and Resend is for email, WAVE is for live and on-demand video.",

  // ── Primary vs differentiator (the #554/#627 correction, locked) ────────────
  // Video is the IDENTITY; agent-native payments are the DIFFERENTIATOR — never the headline.
  primary:
    "video infrastructure — an open protocol and one API for live and on-demand video",
  differentiator:
    "agent-native payments: every capability is payable by an agent over HTTP-402 (x402) on the " +
    "same surface a person uses, with did:wave identity and OFAC screening on the path",
  moneyFraming:
    "The agent-native payment layer — the WAVE Money Engine — powers the WAVE Wallet. It is the " +
    "DIFFERENTIATOR beneath the video infrastructure, never the headline identity. 'Agent money OS' " +
    "is a lowercase category descriptor for that engine, never the brand noun.",

  // ── The two engines + the product (naming LOCKED 2026-06-06) ────────────────
  engines: {
    media: {
      name: "WAVE Media Engine",
      what: "moves the video — in/out, local/global, file/stream — across every transport behind one API",
      surfaces: ["https://wave.online/media-engine", "https://engine.wave.online"],
    },
    money: {
      name: "WAVE Money Engine",
      what: "gets everyone paid — people and agents — on one rail: x402, identity, compliance, metering",
      surfaces: ["https://wave.online/money-engine", "https://money-engine.wave.online"],
    },
  },
  product: {
    name: "WAVE Wallet",
    what:
      "the product face of the Money Engine — a 4-party wallet network (creator + creator's agent ⟷ " +
      "viewer + viewer's agent), so micropayments for video are native on one rail",
    surface: "https://wallet.wave.online",
    status: "planned" as const, // NOT a public product yet — see ../copywriting/claims.ts. Do not assert as available.
  },

  // ── Audiences — always BOTH, never one at the other's expense ───────────────
  audiences: ["the people who make video", "the agents that pay for and consume it"],

  // ── Elevator pitches — pick by length budget ────────────────────────────────
  pitches: {
    oneLiner:
      "One API for live and on-demand video — built for the people who make it and the agents that pay for it.",
    short:
      "WAVE is an open protocol and one API for video. Integrate once; ingest and deliver across every " +
      "transport. Payment, identity, and metering are native — so a person with a key and an agent over " +
      "x402 use the exact same surface.",
    paragraph:
      "WAVE is video infrastructure for the agentic internet. One open protocol and one API move live " +
      "and on-demand video across every transport — SRT, RIST, AES67, OMT, MoQ, HLS, WebRTC and more — " +
      "through a single contract (the WAVE Media Engine). The same surface is agent-native: every " +
      "capability is discoverable and payable by an autonomous agent over HTTP-402 (x402), with " +
      "did:wave identity and OFAC screening on the payment path (the WAVE Money Engine). People build " +
      "with a key; agents transact with a credential — same routes, same enforcement.",
  },

  // ── FORBIDDEN positioning — the gate flags these in user-facing marketing copy ──
  // (Distinct from copywriting's voice gate and claims.ts. This guards the IDENTITY.)
  forbidden: [
    {
      pattern: /\bThe Agent Money OS\b/i,
      why: "Demoted (#627 over-rotation). WAVE IS video infrastructure; 'agent money OS' is a lowercase " +
        "engine descriptor, never the headline brand/tagline. Use the canonical tagline or 'WAVE Money Engine'.",
    },
    {
      pattern: /\bMoney OS\b/,
      why: "Not the brand identity. Use 'WAVE Money Engine' for the engine, 'WAVE Wallet' for the product.",
    },
  ],
} as const;

export type Positioning = typeof POSITIONING;
