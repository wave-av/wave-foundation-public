# Design system: dispatch

The first reusable token set, now the **AI / routing** anchor on the [accent wheel](./accent-wheel.md).
Dark, terminal-native, one confident accent. The full reusable chassis (layout + setup) is documented
in [chassis.md](./chassis.md) and shipped as a scaffold; this file is just dispatch's accent.

## Tokens

```css
:root{
  --bg:   #0b0f14;                /* near-black blue — shared WAVE neutral */
  --fg:   #cfe3f7;                /* soft ice text — shared WAVE neutral */
  --dim:  #5b7287;                /* muted slate (secondary text, borders) — shared */
  --acc:  oklch(0.78 0.15 171);   /* dispatch teal — the one accent (favicon hex #16d6aa) */
  --warn: #e6b450;                /* amber — shared WAVE neutral */
}
/* font: ui-monospace, "SF Mono", Menlo, monospace */
```

The accent is authored in **OKLCH** (the wheel's source of truth); its sRGB rendering `#16d6aa` is
used only for the favicon fill (favicons can't rely on `oklch()`). The neutrals stay hex — they're a
fixed shared constant, not a per-product color choice. See [colors.md](./colors.md) for the rule.

> **Snapped to the grid (2026-05-28):** dispatch originally shipped `#43d9ad` (`oklch(0.796 0.141 169)`),
> a one-off. It's now the AI-family **vivid** anchor `oklch(0.78 0.15 171)` so there are no exceptions
> to the systematic wheel. Subtly more vivid; same teal.

## Rules

- **One accent.** `--acc` carries CTAs, links, active states. No gradients (the favicon is the WAVE
  curled-wave mark recolored flat to the accent, not the WAVE gradient).
- **Mono everywhere.** Reinforces the developer/agent-tool identity.
- **Selection matches the theme** — `::selection{background:var(--acc);color:var(--bg)}` (a real bug
  we hit: the highlight was the wrong color).
- **Mobile + iPad + agent-readable** are first-class, not afterthoughts.

## Reuse for a new product

Don't copy this file — claim an accent from [accent-wheel.md](./accent-wheel.md) and scaffold from
[`new-subdomain-app`](../staging/golden-paths-scaffolds/new-subdomain-app/). Keep the shared
neutrals, the mono type, and the one-accent discipline; the accent is the only thing that changes.
