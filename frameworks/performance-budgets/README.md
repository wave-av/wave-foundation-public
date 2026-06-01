# Performance Budgets

A budget is a number CI enforces, not an aspiration. Every WAVE surface — spokes,
the hub, edge Workers — ships under a fixed weight ceiling so "it got slow" is
caught in the PR that caused it, not in a customer complaint. The spoke chassis is
already built for this: **the content is the control, zero-JS base, JS only
enhances** (see the touch-first UI standard) — these budgets keep it that way.

## The budgets

| Budget | Ceiling (spoke) | Why |
|--------|-----------------|-----|
| **HTML (gzipped)** | ≤ 14 KB | first TCP round-trip delivers a usable page (the classic 14KB window) |
| **JS (gzipped, total)** | ≤ 30 KB | enhancement only; a spoke must be fully usable with JS disabled |
| **CSS (gzipped)** | ≤ 14 KB | one accent chassis; no framework CSS |
| **Fonts** | ≤ 0 by default | system font stack; a webfont is an explicit, justified exception |
| **Requests (initial)** | ≤ 5 | HTML + CSS + (optional) one JS + favicon |
| **LCP** (field/lab) | ≤ 1.5 s | mostly-static content has no excuse |
| **TTI** | ≤ 2.0 s | zero-JS base is interactive immediately; JS must not regress this |
| **CLS** | ≤ 0.05 | reserve space for the auto-spin nav; no layout jump |

Ceilings are per-surface — the hub (dynamic) gets a separate, higher JS budget;
edge Workers budget **cold-start + bundle size**, not page weight. Set them in a
committed `perf-budget.json` per surface; the number lives with the code.

## Enforcement

1. **Static weight gate (required, fast).** A CI step gzips the built assets and
   fails if any category exceeds its ceiling. No browser needed — this is the
   per-PR gate. Fail closed: an unmeasurable artifact counts as over budget.
2. **Lighthouse (advisory → required once stable).** LCP/TTI/CLS/total-byte
   assertions via `lighthouse-ci` against a preview deploy. Start advisory; promote
   to required once the surface is stable (same ratchet as the lint baselines).
3. **Ratchet, don't just cap.** Like the shellcheck/python baselines: record the
   current weight; a PR may not increase it past the ceiling AND may not increase it
   at all without an explicit budget bump in `perf-budget.json` (reviewed change).

```json
// perf-budget.json (per surface)
{ "html_gzip_kb": 14, "js_gzip_kb": 30, "css_gzip_kb": 14,
  "fonts": 0, "initial_requests": 5, "lcp_ms": 1500, "tti_ms": 2000, "cls": 0.05 }
```

## Why these numbers

- **14 KB HTML** — the first congestion window; a page that fits arrives in one
  round trip. Static spokes have no reason to exceed it.
- **0 fonts** — webfonts are the most common silent budget-blower (FOUT/FOIT + 50-200KB).
  The chassis uses the system stack; a brand font is a deliberate, measured exception.
- **30 KB JS** — the auto-spin nav + progressive enhancement fit easily; the ceiling
  exists to stop a framework from sneaking in. If a spoke needs a framework, that's a
  design conversation, not a default.

## Anti-patterns

- ❌ A budget that isn't wired to CI (an aspiration, not a budget).
- ❌ Shipping a webfont "for now" (it's never temporary; it's the #1 regression).
- ❌ Measuring uncompressed sizes (users get gzip/brotli; budget the wire weight).
- ❌ A JS bundle that makes the zero-JS base non-functional (breaks agents + a11y +
  the content-is-the-control principle).
- ❌ Capping but not ratcheting — weight creeps to the ceiling and sits there.

## Relation to other frameworks

- **Touch-first UI standard** — zero-JS base + content-is-the-control is what makes
  these budgets achievable; the budgets keep the standard honest.
- [`tech-debt`](../tech-debt/) — a budget bump is tracked debt; record the carrying cost.
- [`observability`](../observability/) — field LCP/CLS come from RUM; the lab numbers here are the gate.
