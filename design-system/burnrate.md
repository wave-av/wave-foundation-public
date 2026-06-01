# Design System: BurnRate

macOS Electron menubar app. Dark, data-dense, three-state feedback system. Single metric (burn ratio) drives all visual state.

## Tokens

```css
:root {
  /* Backgrounds */
  --bg-primary:   oklch(0.13 0.01 240);   /* near-black */
  --bg-secondary: oklch(0.18 0.01 240);   /* elevated surfaces */
  --bg-popover:   oklch(0.16 0.01 240);   /* popover vibrancy layer */

  /* Text */
  --text-primary:   oklch(0.92 0.01 240); /* primary text */
  --text-secondary: oklch(0.60 0.01 240); /* secondary/muted */

  /* Burn tier colors (the entire product is built around these) */
  --burn-cold: oklch(0.520 0.250 27);     /* red — <33% daily target */
  --burn-warm: oklch(0.680 0.230 60);     /* amber — 33–75% */
  --burn-hot:  oklch(0.590 0.220 140);    /* green — >75% */

  font-family: ui-monospace, "SF Mono", Menlo, monospace;
}
```

## Burn tier logic

| Tier | Threshold | Color token | Meaning |
|------|-----------|-------------|---------|
| Cold | ratio < 0.33 | `--burn-cold` | Leaving money on the table |
| Warm | 0.33 ≤ ratio < 0.75 | `--burn-warm` | Using the subscription moderately |
| Hot | ratio ≥ 0.75 | `--burn-hot` | Cooking. Subscription value maximized |

The UI tray icon, status bar title, and all charts adopt the tier color. Everything communicates one thing: are you getting your money's worth.

## Rules

- **OKLCH only** — no hex, no rgb, no Tailwind color utilities (enforced by CI)
- Use `className="bg-burn-cold"` (semantic token) not `className="bg-red-500"` (Tailwind color)
- Dark mode is the only mode (menubar apps live in the menu bar, always dark)
- All charts (ECharts): `backgroundColor: 'transparent'`, axis colors from `--text-secondary`

## Component patterns

```typescript
// Tray title — shows tier in color + ratio
const tierColor = burnTier === 'hot' ? 'var(--burn-hot)' :
                  burnTier === 'warm' ? 'var(--burn-warm)' : 'var(--burn-cold)';

// Config via Zustand + IPC bridge
import { useBurnStore } from '@/stores/usage-store';
const { tier, ratio, dailyTarget } = useBurnStore();
```

## IPC surface (minimal — only these channels)

- `burnrate:get-config` / `burnrate:set-config`
- `burnrate:refresh-usage`
- `burnrate:usage-data` (push from main)
- `burnrate:theme-change` (push from main)

No other IPC channels. ccusage data flows: main process only (filesystem access) → IPC → renderer.
