# WAVE accent wheel — category hue-families

Every branded WAVE subdomain (`dispatch.`, `clips.`, `pulse.`, …) gets **one accent**. This file is
the palette and the claim registry. It scales to the full ~50-product portfolio while keeping every
accent a readable sibling on the shared `--bg #0b0f14`.

> Infra/regional hosts (`api-eu-1`, `cache`, `capture-dfw`, …) don't render the chassis and get **no
> accent**. Accents are for branded portal subdomains only.

## The system

A flat hue ring tops out at ~10–11 distinguishable colors — far short of the portfolio. So instead
of one ring we use a **2-D system**: a fixed lightness/chroma *envelope*, a **hue band per product
category**, and **tiers within a family**.

- **Fixed envelope.** Vivid tier `L 0.78 / C 0.15`; deep tier `L 0.68 / C 0.13`. Same envelope for
  every family → equal brightness, equal saturation, true siblings (this is why we use OKLCH — L and
  C are perceptually uniform, so holding them constant and walking hue gives even-looking siblings).
- **Hue per category.** The accent *means* something: AI reads teal, analytics green, monetization
  red. 13 anchors, spaced to stay distinguishable.
- **Tiers within a family.** Distinguish products in the same category by the deep-vs-vivid tier
  and/or a ±8–12° hue nudge inside the band.
- **Amber band (75–95°) is reserved** for `--warn` (`#e6b450`) — no accent lives there.

Capacity: 13 families × 2 tiers + intra-family hue steps ≈ **~52 accents**.

## Category anchors

Hex is the sRGB rendering of the OKLCH value (for favicon fills; CSS uses the OKLCH). Contrast is
WCAG vs `--bg #0b0f14`. All values verified by `staging/golden-paths-scaffolds/new-subdomain-app/validators/contrast.mjs`
(re-run it; it is the source of these numbers, not hand-typed).

| # | Family | Hue | Vivid `L.78/C.15` | ratio | Deep `L.68/C.13` | ratio | Example products |
|---|--------|----:|:-----------------:|:-----:|:----------------:|:-----:|------------------|
| 1 | AI / routing / inference | 171 | `#16d6aa` | 10.2:1 | `#14b28d` | 7.1:1 | **dispatch**, cortex, studio-ai, voice |
| 2 | streaming / transport | 195 | `#00d4d5` | 10.4:1 | `#00b0b1` | 7.2:1 | pipeline, moq, srt, broadcast |
| 3 | developer / API / SDK | 220 | `#00ccf9` | 10.1:1 | `#00aacf` | 7.0:1 | sdk-api, api, cli, adk, mcp, workflow |
| 4 | infrastructure / edge | 250 | `#65bdff` | 9.4:1 | `#549de5` | 6.7:1 | fleet, mesh, edge, runtime |
| 5 | production / studio | 280 | `#a5abff` | 9.0:1 | `#898ee7` | 6.5:1 | studio, autopilot, editor |
| 6 | collaboration | 305 | `#ce9dff` | 9.1:1 | `#ab82d8` | 6.3:1 | connect, campus, academy |
| 7 | media / content | 330 | `#ec92e5` | 9.0:1 | `#c579be` | 6.3:1 | clips, captions, chapters, slides-to-video, podcast, archive |
| 8 | social / audience | 355 | `#ff8cbc` | 8.9:1 | `#d6749c` | 6.3:1 | social-distribution, audience-engagement, creator-economy |
| 9 | monetization | 25 | `#ff8e86` | 8.7:1 | `#dd766f` | 6.3:1 | yield, marketplace, billing, vault |
| 10 | communication | 50 | `#ff9858` | 9.1:1 | `#d77e49` | 6.4:1 | telephony, voice/phone, caller |
| 11 | hardware / device | 110 | `#bebf3a` | 9.8:1 | `#9e9f30` | 6.8:1 | companion, wave-node, usb-relay, desktop, flash |
| 12 | analytics | 140 | `#81ce70` | 10.1:1 | `#6bac5c` | 7.0:1 | pulse, radar, business-intelligence |
| 13 | audio / sound | 155 | `#59d38c` | 10.2:1 | `#4ab074` | 7.1:1 | wave-sound, audio |

Contrast targets: `--acc` on `--bg` ≥ 3:1 (UI/large-text floor; vivid tier clears the 7:1 AAA bar,
deep tier ≥ 6.3:1). `--fg #cfe3f7` on `--bg` = 14.6:1.

## OKLCH → hex (favicons)

`--acc` is authored in OKLCH (the source of truth). The favicon needs a **hex** because standalone
SVG favicons render across browsers/OS/unfurlers where `fill="oklch(...)"` is unreliable. Derive it —
never hand-type it:

```bash
node validators/contrast.mjs --hex 0.78 0.15 330   # → #ec92e5
node validators/contrast.mjs 0.78 0.15 330          # → PASS/FAIL gate
```

## Claim registry

One row per branded subdomain so two products never share an accent. Add yours when you scaffold.

| Subdomain | Product | Family | OKLCH | hex | Tier |
|-----------|---------|--------|-------|-----|------|
| `dispatch.wave.online` | Dispatch | AI / routing | `oklch(0.78 0.15 171)` | `#16d6aa` | vivid |
| `clips.wave.online` | Clips (Clip Engine) | media / content | `oklch(0.78 0.15 330)` | `#ec92e5` | vivid |
| `pulse.wave.online` | Pulse | analytics | `oklch(0.78 0.15 140)` | `#81ce70` | vivid |
| `moq.wave.online` | MoQ Live | streaming / transport | `oklch(0.78 0.15 195)` | `#00d4d5` | vivid |
| `ndi.wave.online` | NDI | streaming / transport | `oklch(0.78 0.15 183)` | `#00d6c0` | vivid −12° |
| `dante.wave.online` | Dante | streaming / transport | `oklch(0.78 0.15 207)` | `#00d1e8` | vivid +12° |
| `srt.wave.online` | SRT | streaming / transport | `oklch(0.68 0.13 195)` | `#00b0b1` | deep |
| `omt.wave.online` | OMT | streaming / transport | `oklch(0.68 0.13 207)` | `#00aec1` | deep +12° |
| `bridge.wave.online` | Bridge (any↔any gateway) | infrastructure / edge | `oklch(0.78 0.15 250)` | `#65bdff` | vivid |
| `api.wave.online` | Gateway (auth/scope/meter) | developer / API | `oklch(0.78 0.15 220)` | `#00ccf9` | vivid |
| `voice.wave.online` | Voice | communication | `oklch(0.78 0.15 50)` | `#ff9858` | vivid |
| `phone.wave.online` | Phone | communication | `oklch(0.68 0.13 50)` | `#d77e49` | deep |
| `captions.wave.online` | Captions | media / content | `oklch(0.68 0.13 330)` | `#c579be` | deep |
| `chapters.wave.online` | Chapters | media / content | `oklch(0.78 0.15 318)` | `#df97f5` | vivid −12° |
| `podcast.wave.online` | Podcast | media / content | `oklch(0.68 0.13 342)` | `#ce76af` | deep +12° |
| `editor.wave.online` | Editor | production / studio | `oklch(0.78 0.15 280)` | `#a5abff` | vivid |
| `collab.wave.online` | Collab | collaboration | `oklch(0.78 0.15 305)` | `#ce9dff` | vivid |
| `studio-ai.wave.online` | Studio AI | AI / routing | `oklch(0.68 0.13 171)` | `#14b28d` | deep |
| `transcribe.wave.online` | Transcribe | audio / sound | `oklch(0.78 0.15 155)` | `#59d38c` | vivid |
| `sentiment.wave.online` | Sentiment | analytics | `oklch(0.68 0.13 140)` | `#6bac5c` | deep |
| `search.wave.online` | Search | infrastructure / edge | `oklch(0.68 0.13 250)` | `#549de5` | deep |

**Streaming family is the crowded one** (5 transport products). It uses both tiers plus ±12° hue
nudges inside the band: `moq` holds the vivid anchor, `ndi`/`dante` nudge vivid, `srt`/`omt` take the
deep tier — all stay perceptually distinct cyans on the shared `--bg`. All rows contrast-verified.

> **Dispatch note:** dispatch originally shipped a one-off `#43d9ad` (`oklch(0.796 0.141 169)`). As of
> this wheel it is **snapped onto the grid** to the AI-family vivid anchor `#16d6aa` — no exceptions
> to the system on day one (decision: Jake, 2026-05-28).

## Claiming the next product

1. Pick the **family** (category) and a free **tier** (`vivid` first, then `deep`). If both are taken,
   nudge the hue ±8–12° inside the band — and re-run the contrast gate.
2. `node validators/contrast.mjs <L> <C> <hue>` → must PASS. Grab the hex with `--hex`.
3. Set `ACCENT_OKLCH` + `ACCENT_HEX` in `tokens.css.ts` and `ACC_HEX` in `favicon.ts`.
4. Add a row to the registry above.

See [`chassis.md`](./chassis.md) for the layout/setup the accent drops into, and
[`colors.md`](./colors.md) for the cross-project color discipline.
