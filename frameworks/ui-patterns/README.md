# ui-patterns — the shared spoke surface

The cross-product UI every WAVE edge surface (spoke) shares: a **touch-first product-nav**
and a **multi-column brand/legal footer**, plus the page shell that hosts them. This
framework is the *standard* — the rule that there is **one** implementation and spokes
**consume** it, never hand-roll a copy.

> Promoted from the spoke chassis after the pattern proved out in 2+ spokes
> (`wave-www` + `wave-developer`). See `frameworks/harvest/audit-2026-05-31.md` for the
> audit that cleared promotion (tasks #120 harvest → #121 promote).
>
> **Design re-based on the apex (#164).** The apex (`wave-www`, wave.online) is now the canonical
> DESIGN STANDARD: its tokens, humanist-sans typography, gateway-blue accent (`#00ccf9`), and
> marketing component CSS were promoted back into `@wave-av/spoke-chassis` (`tokens.css.ts` +
> `chassis.css.ts`). Spokes adopt **v0.2.0** to inherit the apex design — see
> `design-system/chassis.md`.

## The one rule

**Do not re-implement the nav or footer in a spoke.** Import them from the canonical
package. Every spoke that copy-pastes the chassis is drift waiting to happen — a brand
tweak, a new product, or a legal-link change then has to be chased across N repos instead
of bumped once.

The canonical implementation is the published package **`@wave-av/spoke-chassis`**
(GitHub Packages, `wave-av`-internal — not public npm). This framework documents the
contract; the package ships the code.

## What the pattern is

### Touch-first product-nav

A sticky cross-product switcher where **the bar itself is the scroll surface** — native
swipe/drag on touch, no custom carousel. Properties that make it the standard:

- **Zero-JS base.** The bar scrolls by touch/drag/wheel with no script. The auto-spin is a
  progressive enhancement served at `/_wave/nav.js` under a strict `script-src 'self'` CSP.
- **Auto-spin that yields to humans.** The marquee drifts, then pauses on any
  `pointer/touch/focus/wheel` input and resumes ~2.2s after the user lets go.
- **Gapless infinite loop** in both directions (duplicated track + edge teleport).
- **Accent-aware.** The current spoke's product is outlined in its own accent
  (`color-mix` in OKLab); accents come from the design-system wheel.
- **a11y parity.** Skip-to-content link + visible focus rings in the spoke accent;
  respects `prefers-reduced-motion`.

### Multi-column brand/legal footer

A marketing-grade footer band: brand + per-spoke CTA (with a live typewriter rotation of
the product's capabilities, first phrase static for no-JS), link columns, social, trust
badges, copyright. Dark-chassis, responsive, zero-JS. It is **not** a product switcher —
that's the top nav.

Legal links are **proxied from the canonical source** (`wave.online`), never duplicated
per spoke — the same single-source rule as the nav.

## The contract (what the package exports)

From `@wave-av/spoke-chassis`:

| Export | Purpose |
|--------|---------|
| `topNavHTML(currentId)` | the sticky product switcher; `currentId` = this spoke's product id |
| `footerHTML(name, year?, cta?)` | the full footer; `cta: FooterCTA` overrides labels/links + typewriter `phrases` |
| `NAV_CSS` | chassis CSS for nav + footer (append AFTER `chassis.css` so it wins) |
| `NAV_JS` | the `/_wave/nav.js` progressive-enhancement script (auto-spin) |
| `WAVE_PRODUCTS` / `WAVE_MASTER` | the product list the nav renders (id, name, url, accent, status) |
| `LEGAL_LINKS` / `LEGAL_ORIGIN` / `isLegalPath()` | the proxied legal-link set + path guard |
| `shell({ product, title, description, url, inner, tokensCss })` | the page shell that hosts nav + body + footer |

```ts
import { shell, topNavHTML, footerHTML, NAV_CSS, NAV_JS } from "@wave-av/spoke-chassis";
// the spoke supplies only its product id, content, and accent tokens — never the nav/footer markup.
```

Adding a product = one entry in `WAVE_PRODUCTS` in the package, then a package bump every
spoke picks up — not an edit in N spokes.

## How a spoke consumes it

1. Route the `@wave-av` scope to GitHub Packages and auth with `read:packages`:

   ```ini
   # .npmrc
   @wave-av:registry=https://npm.pkg.github.com
   //npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}
   ```

2. `npm i @wave-av/spoke-chassis`, then build the page from `shell(...)` + `makeFetch(...)`.
3. Override only spoke-specific bits via the `meta`/`FooterCTA` inputs (product id, accent,
   tagline, CTA links, typewriter phrases). Everything structural comes from the package.

## Migration: retire the local copies

The 2026-05-31 harvest audit found `wave-www` and `wave-developer` each carry a **local,
byte-identical copy** of the nav + footer render instead of importing the package — exactly
the drift this standard exists to kill. The migration for each spoke:

1. `npm i @wave-av/spoke-chassis`.
2. Replace the local `header()`/`footer()`/`shell()` with the package imports.
3. Move any spoke-specific overrides into the `meta`/`FooterCTA` inputs.
4. Delete the local copy; the spoke's `invariants.spec.ts` (see `frameworks/edge-proxy`,
   backlog) confirms the rendered surface is unchanged.

## See also

- `packages/spoke-chassis/README.md` — the canonical implementation + full page set
- `design-system/` — the OKLCH accent wheel the nav/footer pull from
- `frameworks/copywriting/` — the voice/tone + claims rules the footer CTA must pass
- `frameworks/harvest/audit-2026-05-31.md` — the audit that promoted this pattern
