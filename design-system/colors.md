# Cross-Project Color Principles

All WAVE projects use **OKLCH semantic tokens**. This document defines the discipline. The full
palette of per-product accents lives in [accent-wheel.md](./accent-wheel.md); the layout/setup the
accent drops into is [chassis.md](./chassis.md). Each product's specific values are in its own file.

## The one-accent rule

Every product gets:

- `--bg` — near-black background
- `--fg` — primary text (high contrast on bg)
- `--fg-strong` — high-contrast headings / brand wordmark (`#fff`)
- `--acc` — **one accent color** (CTAs, links, active states, progress)
- `--warn` — amber/yellow for warnings
- `--dim` — muted secondary text, borders, placeholders
- `--card` — panel/card surface (one step up from `--bg`)
- `--line` — hairline borders / dividers

> Promoted from the apex (wave.online) design (#164): `--fg-strong`, `--card`, and `--line` are now
> first-class semantic tokens. The chassis component CSS references these instead of hardcoding
> `#fff` / `#0e141b` / `#1c2733`, so a whole surface re-themes from the one `:root` block.

**One accent.** No gradients on the primary accent — gradients are reserved for the WAVE master brand
mark only. Each product's favicon is the WAVE wave mark recolored **flat** to its accent. The
one-accent rule enforces visual focus — users know exactly where to look.

## Typography discipline

**Default = humanist sans** (`ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`).
Promoted from the apex (wave.online, #164): the WAVE consumer + platform surface is humanist sans —
it reads as a product people use, not just a dev tool. **Monospace is retained only for `code` and
`pre`** (ascii diagrams / snippets), where it carries developer/agent-tool meaning. (The original
"mono everywhere" rule applied to the early terminal-native dispatch portal; the apex superseded it
as the design standard.)

## Accessibility baseline

- `--bg` to `--fg` contrast ratio: minimum 7:1 (WCAG AA for small text, AAA for normal)
- `--acc` on `--bg`: minimum 3:1 for large text / UI components
- `::selection { background: var(--acc); color: var(--bg); }` — always set, always theme-matched

## Creating a new product token set

1. Keep `--bg/--fg/--dim/--warn` identical to the shared WAVE neutrals (stays recognizably WAVE)
2. Claim a new `--acc` from the category hue-family wheel — see [accent-wheel.md](./accent-wheel.md)
3. Test WCAG contrast (the wheel's `contrast.mjs` is the gate — it must PASS before shipping)
4. Scaffold from [`new-subdomain-app`](../staging/golden-paths-scaffolds/new-subdomain-app/)

## Product token sets

| Product | File | Accent |
|---------|------|--------|
| Dispatch (AI / routing anchor) | `dispatch.md` | Teal `oklch(0.78 0.15 171)` → favicon `#16d6aa` |
| Every other subdomain | `accent-wheel.md` | One per category hue-family (~52 accents) |
| BurnRate | `burnrate.md` | Red/amber/green tier system |

## OKLCH syntax reminder

```css
oklch(lightness chroma hue)
/* lightness: 0–1 (0=black, 1=white) */
/* chroma: 0–0.37+ (0=gray, higher=more colorful) */
/* hue: 0–360 degrees */

oklch(0.520 0.250 27)   /* red-ish */
oklch(0.680 0.230 60)   /* amber */
oklch(0.590 0.220 140)  /* green */
oklch(0.770 0.155 171)  /* teal (dispatch accent) */
```

**Author accents in OKLCH** — never pick an accent as hex (`#3b82f6` is an sRGB artifact with no
perceptual meaning, and the wheel's even spacing only works in OKLCH). Hex appears in exactly two
sanctioned places: (1) the **favicon fill**, derived from the accent OKLCH because standalone SVGs
can't rely on `oklch()`; (2) the **fixed shared neutrals** (`--bg/--fg/--dim/--warn`), which are a
frozen WAVE constant, not a per-product color decision.
