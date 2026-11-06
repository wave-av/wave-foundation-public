# Per-product icon spec (not yet built — this is the spec, not the set)

Jake, 2026-09-01, on the mobile nav: *"i like how the navbar menu on mobile, but i think its a lot
of waves, maybe we should have the names of the products in the COLOR that it is and get rid of the
logo? or start to make the ICONS for EACH product, because that is REQUIRED for the console
eventually too."*

He named two options and said they're both wanted eventually. **They are not exclusive — this is a
sequence, not a fork:**

1. **Ship now: color-name treatment.** Every product's name renders in its own registry accent
   (`WAVE_PRODUCTS[].accent`), and the repeated wave-mark glyph is gone — replaced by a plain color
   swatch (`.miswatch` / the desktop `.pi.cur .pn::before` dot), not a per-product icon. See
   `packages/spoke-chassis/src/nav-mobile.ts`, `nav-mobile-assets.ts`, `nav-products-assets.ts`. This
   is fast, needs no new asset pipeline, and directly answers "a lot of waves" — every row is now a
   distinct color instead of a distinct-but-identical glyph.
2. **Follow-up: a real per-product icon set.** This doc is the spec for it. **Not shipped in this
   pass** — a coherent 36+-glyph set (one grid, one stroke weight, one visual logic, legible at both
   nav size and console size) is a genuine design project, not something to rush inside a nav-identity
   PR. A half-set (some products with a bespoke glyph, most still on a plain swatch) reads as broken
   next to the products that lack one — worse than shipping no icons at all. So: color-name now, the
   icon set as its own tracked, reviewed pass.

The swatch built in step 1 is deliberately the SAME slot (`.miswatch`, 9×9, `flex:0 0 auto`, directly
before the name) a real per-product `<svg>` drops into later — swapping the fill-only chip for an
icon component is a one-line change per row, not a re-layout.

## Why this needs a spec before glyphs get drawn

`WAVE_PRODUCTS` (nav.ts) currently lists 36 menu products across 4 engines (Media, Money, Dispatch,
Trust) and 5 planes inside Media (Transports, Studio, Intelligence, Deliver, Infrastructure), plus 2
utility surfaces (Changelog, Partners). A 36-glyph icon set needs a shared visual grammar or it reads
as 36 unrelated stickers — the exact "half-set looks broken" failure mode, just at full scale instead
of half.

## Grid + stroke (proposed, to be locked before drawing)

- **Canvas:** 24×24 viewBox, geometry drawn inside a 20×20 safe area (2px padding) — legible down to
  16px (nav-size) without redrawing, scales cleanly up to console-size (32–40px) since it's a single
  source SVG, not a bitmap.
- **Stroke:** 1.5px at 24×24 (matches the nav chevron/menu-button glyphs already in `nav-assets.ts` /
  `nav-products.ts`, e.g. the Products-menu chevron's `stroke-width="1.6"` — close enough to read as
  the same family, not a mismatched import). Outline style, not filled shapes — fills don't recolor
  cleanly per product and read heavier than the current typographic nav.
- **Corners:** `stroke-linecap="round"`, `stroke-linejoin="round"` everywhere (same as the existing
  chevron/hamburger glyphs) — one joinery rule, not a per-icon choice.
- **Color:** `fill="none" stroke="currentColor"` — the icon inherits `color`, so it rides the SAME
  `--identity-mix`-gated color-mix the name text uses (`.miname`/`.pi .pn`) with zero new CSS. No
  gradients (WAVE's one-gradient rule reserves gradients for the master wordmark only, per
  `colors.md`).
- **Component shape:** `WaveIcon({ id, size })` exported from `@wave-av/spoke-chassis`, a lookup table
  keyed by `WaveProduct.id` (not `name` — ids are the registry's stable key) that falls back to a
  neutral generic mark (NOT the old wave-mark — a plain shape, e.g. a rounded square outline) for any
  product without a drawn glyph yet, so a partial rollout never regresses to "half broken."

## Metaphor per product (grouped by plane/engine — the same grouping the nav already uses)

Filling in one clear, literal metaphor per product before drawing avoids the generic-icon trap
(abstract blobs that don't teach anything). Starter mapping, grouped the way the Products menu and
mobile drawer already group (`ENGINE_ORDER` / `PLANE_ORDER` in `nav-products.ts`) — a reviewer checks
this table, not 36 loose ideas:

| Plane / engine | Products | Metaphor direction |
|---|---|---|
| Transports | MoQ, NDI, Dante, OMT, SRT, Realtime, Phone | a directional signal/pulse glyph, varied by a small distinguishing mark per protocol (not a full redraw each time) |
| Studio | Clips, Editor, Collab, Podcast, Studio AI | a frame/timeline glyph family (clip corner marks, a playhead, a mic capsule) |
| Intelligence | Voice, Captions, Chapters, Transcribe, Sentiment, Search, Acuity, Enhance | a waveform/analysis glyph family (bars, a caption bracket, a magnifier) |
| Deliver | Media, Crest, Listen, Badge | an output/broadcast glyph family (an arc, a badge outline, a play triangle) |
| Infrastructure | Codec, Metrics, Email, GPU | a system glyph family (a gauge, an envelope, a chip outline) |
| Money | Gateway | a key/meter glyph |
| Dispatch | Dispatch, Bridge, Interchange | a routing/branch glyph |
| Utility | Changelog, Partners | not menu items today (no `engine`); lowest priority for a first icon pass |

## What ships when

- **This PR:** color-name treatment (item 1 above) + this spec, no icons.
- **Next (tracked separately):** draw the grid/stroke prototype for ONE plane (recommend Transports —
  the most crowded, so it's the hardest test of "one visual logic, many products"), get it reviewed
  against this spec, then extend plane by plane. Never ship a plane half-drawn.
- **Console:** once `WaveIcon` exists in `@wave-av/spoke-chassis`, the console (a separate repo/app)
  imports the SAME component/lookup rather than redrawing its own set — that's the point of building
  this as a package export, not inline nav markup, from the start.
