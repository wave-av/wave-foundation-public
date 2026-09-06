# WAVE Positioning — the identity SSOT

_Foundation standard. The canonical answer to **"what is WAVE?"** — the single source every surface
(apex, spokes, docs, agent endpoints, READMEs, decks) keeps consistent with._

This framework owns **identity, narrative, and the canonical strings**. It sits above its two sisters:

| Framework | Owns | The question it answers |
|---|---|---|
| **positioning** (this) | identity · narrative · canonical strings · engine/product naming | **What is WAVE?** |
| [copywriting](../copywriting/voice-and-tone.md) | voice · tone · person/agent register | **How do we say it?** |
| [copywriting/claims](../copywriting/claims.ts) | substantiated / inProgress / required | **What may we assert?** |

## The locked positioning (Jake, 2026-06-06; re-framed 2026-09-02)

> **WAVE is media infrastructure for the agentic internet:** one call shape moves live and on-demand
> media across every transport, and both kinds of user, people and agents, discover it, call it, and
> pay for it per call.

- **Media infrastructure is the identity.** Four facts carry it (`POSITIONING.frame`): two kinds of
  user · one call shape across every transport · paid per call by either kind · discoverable by agents
  (MCP, agent card, skills index). Agent-native access and payment is the **differentiator**, never the
  headline.
- **Capabilities live inside the frame.** "Video API", "transcription API", "streaming platform" are
  what a caller does with WAVE; they are listed beneath the identity and never promoted to it. The
  gate flags `WAVE is a video API` and the superseded `video infrastructure for the agentic internet`.
- **Counts come from the skills index.** `POSITIONING.discovery.counts` is measured from
  `gateway.wave.online/.well-known/wave-skills.json` and dated; re-measure before citing.
- **Truth law binds every string.** No SOC 2 claim for WAVE itself (vendors attributed); no "first on
  x402"; the legal entity is exactly `WAVE Online, LLC`; say "person", never "human".
- **"Agent money OS"** is a lowercase descriptor for the payment *engine* — **never the brand noun**.
  (This corrects the #627 over-rotation that made the OS the tagline.)
- **Naming, locked:** `WAVE Media Engine ⟷ WAVE Money Engine ⟷ WAVE Dispatch Engine` + `WAVE Wallet`
  · `money-engine.wave.online` (marketing) · `dispatch.wave.online` (live, priced per decision)
  · `wallet.wave.online` (product, **planned** — not yet shipped).
- **The engine rule:** a pillar is billed as an *engine* when it has a live product surface, an apex
  page, and a priced capability (a meter family at the gateway). Media, Money, Dispatch clear all three.
  **Trust** (`wave.online/trust` + `trust.wave.online`, machine-readable) clears two and has no meter, so
  it is a *pillar* beside the engines. **Agents** are an *audience*, never a pillar.

## Files

- **`positioning.ts`** — the machine-readable SSOT. Identity, tagline, analogy, the four-fact frame,
  capabilities-inside-the-frame, engine/product naming, agent-discovery surfaces and dated counts,
  audiences and per-audience lines, elevator pitches, and the FORBIDDEN-phrase list. **Surfaces should import these strings**
  (via `@wave-av/messaging`, task #138) rather than re-type them, so the story can't drift.
- **`narrative.md`** — the long-form platform story (the source for the public `/story` surface, #140).
- **`positioning-check.sh`** — the drift gate. Flags positioning-breaking copy (e.g. "The Agent Money
  OS" as a headline, tagline drift) in user-facing files. Wired into CI alongside the copywriting gate.

## Usage

```bash
# check specific files
frameworks/positioning/positioning-check.sh path/to/copy.ts

# CI (changed files vs default branch)
frameworks/positioning/positioning-check.sh --changed

# pre-commit (staged files)
frameworks/positioning/positioning-check.sh --staged
```

Exit 1 on any ERROR-severity drift; WARN prints but does not fail.

## How surfaces consume it

1. **Import, don't re-type.** Pull `POSITIONING.tagline`, `.pitches.short`, `.engines.money.name`, etc.
   from the canonical strings (`@wave-av/messaging` re-exports `positioning.ts`).
2. **Stay inside the identity.** If a page's headline contradicts `POSITIONING.identity`, the page is
   wrong. Media infrastructure primary; capabilities beneath; payments differentiate.
3. **The gate backs it.** `positioning-check.sh` (twin of the copywriting gate) fails CI on drift, so
   the SSOT is enforced, not merely documented.

Changing the positioning is a **governed** act: edit `positioning.ts` in a PR; the gate and reviewers
check it. The strings here are canonical for the whole estate.
