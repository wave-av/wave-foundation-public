# WAVE Positioning — the identity SSOT

_Foundation standard. The canonical answer to **"what is WAVE?"** — the single source every surface
(apex, spokes, docs, agent endpoints, READMEs, decks) keeps consistent with._

This framework owns **identity, narrative, and the canonical strings**. It sits above its two sisters:

| Framework | Owns | The question it answers |
|---|---|---|
| **positioning** (this) | identity · narrative · canonical strings · engine/product naming | **What is WAVE?** |
| [copywriting](../copywriting/voice-and-tone.md) | voice · tone · human/agent register | **How do we say it?** |
| [copywriting/claims](../copywriting/claims.ts) | substantiated / inProgress / required | **What may we assert?** |

## The locked positioning (Jake, 2026-06-06)

> **WAVE is video infrastructure for the agentic internet** — an open protocol and one API for live
> and on-demand video, built for the people who make it and the agents that pay for it.

- **Video is the identity.** Agent-native payments are the **differentiator**, never the headline.
- **"Agent money OS"** is a lowercase descriptor for the payment *engine* — **never the brand noun**.
  (This corrects the #627 over-rotation that made the OS the tagline.)
- **Naming, locked:** `WAVE Media Engine ⟷ WAVE Money Engine ⟷ WAVE Wallet`
  · `money-engine.wave.online` (marketing) · `wallet.wave.online` (product, **planned** — not yet shipped).

## Files

- **`positioning.ts`** — the machine-readable SSOT. Identity, tagline, analogy, engine/product naming,
  audiences, elevator pitches, and the FORBIDDEN-phrase list. **Surfaces should import these strings**
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
   wrong. Video primary; payments differentiate.
3. **The gate backs it.** `positioning-check.sh` (twin of the copywriting gate) fails CI on drift, so
   the SSOT is enforced, not merely documented.

Changing the positioning is a **governed** act: edit `positioning.ts` in a PR; the gate and reviewers
check it. The strings here are canonical for the whole estate.
