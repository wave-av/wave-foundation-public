# WAVE subdomain chassis

The reusable layout + setup behind every WAVE subdomain portal, proven on `dispatch.wave.online` and
extracted so the next ~50 spokes are siblings out of the box. This documents the *what and why*; the
runnable templates live in [`staging/golden-paths-scaffolds/new-subdomain-app/`](../staging/golden-paths-scaffolds/new-subdomain-app/).

## What it is

Dark, humanist-sans, **one accent**, marketing-grade — served **straight from the edge worker as
HTML/CSS strings**. No Next.js, no Tailwind, no build step. That's deliberate: it *is* the
thin-CF-Worker-spoke pattern the subdomain program settled on. Auth and metering federate through the
WAVE gateway (`api.wave.online`); the spoke stays thin and presentational.

> **The design standard is now the apex (wave.online), promoted in #164.** The chassis originated as
> the terminal-native dispatch portal (mono, centered single card). The apex evolved it into the WAVE
> marketing design language: humanist sans typography, the gateway-blue accent (`#00ccf9`), a
> top-anchored max-1040 column, and a full marketing component set (hero, grid/card, pricing plans,
> pill rows, a touch product rail, a CTA block, and verbatim legal/long-form body). `code`/`pre`
> remain monospace. That apex look now lives in `chassis.css.ts` and is what every spoke inherits.

## The one swap point

A new spoke inherits everything and changes the accent in **one place** — `tokens.css.ts` — claimed
from [`accent-wheel.md`](./accent-wheel.md):

1. `ACCENT_OKLCH` → `--acc` in CSS
2. `ACCENT_HEX` → its derived hex; `favicon.ts` imports it, so the mark never drifts from the token

Everything below is identical across all spokes.

## The four pieces

| Piece | Template | What it carries |
|---|---|---|
| **Tokens** | `tokens.css.ts` | `:root` palette — `--bg/--fg/--fg-strong/--dim/--warn/--card/--line` fixed, **only `--acc` varies**; themed `::selection` |
| **Component CSS** | `chassis.css.ts` | the apex marketing design language — never edited per product |
| **Shell** | `shell.ts` | `shell()` → full page: doctype, SEO + OpenGraph meta, favicon link, CSP, header card, footer |
| **Favicon** | `favicon.ts` | the WAVE curled-wave mark recolored flat to the accent (hex) |

## The class vocabulary

The whole apex-derived look comes from a small, fixed set of classes — a spoke *composes* these,
never invents CSS:

- **Layout** — `body`, `.wrap` (centered max-1040 container), `section`, `.top` (header row), `.foot` (footer)
- **Text** — `.kicker` (accent eyebrow), `.lead` / `.sub` (muted lede), `.acc` / `.warn` / `.dim` / `.good`, `h1` / `h2` / `h3`, `code`
- **Marketing** — `.hero`, `.grid`, `.card`, `.trust`+`.tag` (pills), `.prods` (touch product rail), `.cta` (closer block), `.plan` / `.plan.featured` (pricing)
- **Blocks** — `pre` (ascii flow diagrams, mono), `.box` (bordered panel), `.row`/`.r`+`.k`/`.kk` (label:value lines)
- **Nav / CTA** — `.btn` / `.btn.primary` / `.btn.ghost` (buttons), `a` (accent links)
- **Legal** — `.legal-body` (verbatim long-form legal/about copy)
- **Inputs** — `input` / `select` (dark fields, for calculators/forms)

## Rules (the design's discipline)

- **One accent.** `--acc` carries CTAs, links, active states, and the favicon. No gradients on the
  accent — gradients are for the WAVE brand mark only, never the flat product accent.
- **Humanist sans body** — `ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`.
  The apex (wave.online) design standard. Monospace is retained only for `code` and `pre`
  (snippets / ascii diagrams), where it carries developer/agent-tool meaning.
- **Selection matches the theme** — `::selection{background:var(--acc);color:var(--bg)}`. (A real bug
  the dispatch portal hit: the highlight was the wrong color.)
- **Favicon fill is hex, not `oklch()`** — favicons render in many contexts where `oklch()` isn't
  supported; derive the hex from the accent OKLCH via `validators/contrast.mjs`.
- **Mobile + iPad + agent-readable are first-class** — the `@media(max-width:480px)` block and the
  `/llms.txt`-style machine surfaces are part of the chassis, not afterthoughts.
- **Spokes carry no auth** — federate through the gateway; keep the spoke thin and presentational.

## Standard page set

Beyond the `/` + `/favicon.svg` + `/health` front-door, the chassis serves the public surfaces every
mature WAVE product (dispatch) has — derived from one `SpokeMeta`, so a spoke gets them for free.
Pass `meta` to `makeFetch(landingPage, FAVICON_SVG, { meta })` and these light up
([`templates/pages.ts`](../staging/golden-paths-scaffolds/new-subdomain-app/templates/pages.ts)):

| Surface | What | Notes |
|---|---|---|
| `GET /status` | health + dependency rows (HTML) | `?format=json` for machines; pass a `status()` producer for live checks |
| `GET /transparency` | data + logging policy | default copy reflects the thin-edge invariant; append product clauses via `transparencyExtra` |
| `GET /robots.txt` | crawl directives + sitemap hint | static |
| `GET /sitemap.xml` | URL set | from `sitemapPaths` (default `/`, `/status`, `/transparency`) |
| `GET /llms.txt` | agent discovery | points agents at the gateway; extend with `llmsExtra` |
| `404` / federation miss | branded error page | replaces the plain-text 404 when `meta` is set |

All HTML pages reuse `shell()` → same accent, CSP, SEO head. The 2-arg `makeFetch(landingPage, favicon)`
form still works (front-door only) — the page set is **opt-in and back-compatible**. Richer per-spoke
or per-product surfaces (docs, pricing, dashboard, `/.well-known/x402`, `/openapi.json`) compose on top;
see the dispatch surface inventory for the full P0/P1/P2 map.

## Provenance

Originally extracted from `wave-dispatch-demo/edge-router/{worker,content,auth-portal}.ts` (the live
dispatch portal). The favicon path is still lifted verbatim. The **design language was re-based on the
apex (wave.online) in #164** — its tokens, humanist-sans typography, gateway-blue accent, and marketing
component CSS were promoted into `tokens.css.ts` + `chassis.css.ts` so a new spoke is visually
indistinguishable from the apex except for its claimed accent. The nav/footer/SEO/consent/CTA infra
(the product switcher, multi-column footer, OG/JSON-LD, first-party analytics) is richer than the apex's
local copy and remains the standard the apex itself documents.
