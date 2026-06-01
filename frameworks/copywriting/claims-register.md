# WAVE Claims Register — the data model behind "only ship what's true"

_Foundation standard. The companion to `voice-and-tone.md`: where the copy-checker is the **idea
gate** (it flags unsubstantiated marketing patterns in prose), the claims register is its **data
model** — a per-surface, single source of truth for every assertion a surface is allowed to make._

_Proven identical in `wave-av/wave-www` (`content/claims.ts`) and `wave-av/wave-developer`
(`content/claims.ts`); harvested here as the canonical model._

## Why this exists

WAVE has near-zero customers. Fabricated metrics, ROI figures, and social proof are a real risk —
not because anyone is dishonest, but because legacy marketing copy carries numbers (`347% ROI`,
`4.8★ from 250 reviews`, `99.99% uptime`) that nothing backs. The copy-checker can flag _patterns_,
but it can't decide whether a specific number is true. The claims register makes that decision
explicit, reviewable, and enforceable: every assertion is recorded with a status, and **only proven
claims render**.

## The model

```ts
export type ClaimStatus = "substantiated" | "inProgress" | "required";

export interface Claim {
  id: string;        // stable kebab-case id, e.g. "open-protocol"
  text: string;      // the exact assertion as it would appear in copy
  status: ClaimStatus;
  backing?: string;  // what substantiates it (only meaningful when substantiated)
  note?: string;     // why it's withheld (for inProgress / required)
}
```

The canonical type ships at `frameworks/copywriting/claims.ts`. A surface copies these types and
declares its own `CLAIMS: Claim[]` register.

## The rule

> **Only `substantiated` claims may be rendered in live copy.**

`inProgress` and `required` claims are tracked in the register so they are visible and accounted
for — but they MUST NOT appear in any user-facing string until promoted. Live copy is built only
from the filtered set:

```ts
import { renderable } from "../frameworks/copywriting/claims";
import { CLAIMS } from "./claims"; // this surface's register

const safe = renderable(CLAIMS); // -> only substantiated claims
```

### The three statuses

| Status | Meaning | Renders? |
|---|---|---|
| `substantiated` | Backed by real evidence — a shipped feature, a live legal page, the actual infra stack, a public measurement. | **Yes** |
| `inProgress` | Has a path to truth but isn't backed yet — no measurement, no certificate, a count that drifts. | No (until promoted) |
| `required` | Desired but unsupported, often fabricated (e.g. ROI with zero customers). Recorded so it is explicitly refused, not silently re-introduced. | **Never** |

## The workflow

A claim moves toward truth, never away from it:

1. **`required`** — Someone wants to make the assertion, but nothing backs it. Add it to the
   register with a `note` explaining why it is withheld (e.g. _"WAVE has ZERO customers —
   fabricated. Never render."_). This is a record of a refused claim, not a TODO to fake it.
2. **`inProgress`** — A path to substantiation appears: a status page is planned, a measurement is
   queued, a certification is being pursued. Keep the `note` pointing at what's missing.
3. **`substantiated`** — The evidence is proven and durable. Set `backing` to the concrete evidence
   (a legal page slug, the real package name, the infra vendor) and drop the `note`. The claim now
   passes `renderable()` and may appear in copy.

Demotion is allowed: if backing is withdrawn (a vendor changes, a cert lapses), move the claim back
and it stops rendering automatically.

## Examples (from the proven spokes)

**Rendered — substantiated:**

```ts
{ id: "open-protocol", status: "substantiated",
  text: "An open protocol and one API for video — for humans and agents.",
  backing: "Product positioning; openapi.yaml + x402 surface are real." }

{ id: "infra-partners", status: "substantiated",
  text: "Built on Cloudflare, Supabase, and Stripe.",
  backing: "Actual infra stack." }
```

**Withheld — inProgress (a path exists, but no proof yet):**

```ts
{ id: "uptime", status: "inProgress", text: "99.99% uptime",
  note: "CONTRADICTS shipped SLA (99.5/99.9/99.95 by tier). Use SLA tiers or omit." }

{ id: "soc2", status: "inProgress", text: "SOC 2 Type II certified",
  note: "No certification evidence — do not claim certified." }
```

**Refused — required (fabricated; never render):**

```ts
{ id: "roi", status: "required", text: "$847K saved / 347% ROI",
  note: "WAVE has ZERO customers — fabricated. Never render." }

{ id: "social-proof", status: "required", text: "'trusted by' / 4.8★ from 250 reviews",
  note: "No customers/reviews exist. Never render." }
```

## How it integrates with the copy-checker

The two halves of the copywriting framework are complementary:

- **`copy-checker.sh` — the idea gate.** Pattern-matches prose for forbidden constructs (salesy
  urgency, vague errors, non-inclusive terms, buzzwords, unsubstantiated superlatives). It runs on
  every PR touching user-facing copy and is content-agnostic — it can't know whether `347% ROI` is
  true, only that an unbacked number is suspicious.
- **`claims.ts` + a surface's register — the data model.** Decides, per claim, what is true. Live
  copy is _built from_ `renderable(CLAIMS)`, so a withheld claim can't reach a page in the first
  place — the checker never even sees it because it was never rendered.

Together: the register prevents unsubstantiated claims from being authored into copy; the checker
catches anything that slips into prose by hand.

## Applying to a surface

1. Copy `ClaimStatus`, `Claim`, and `renderable` from `frameworks/copywriting/claims.ts` (or import
   them if the surface vendors the framework).
2. Create the surface's `claims.ts` with a `CLAIMS: Claim[]` register. Audit every existing
   marketing number/superlative/social-proof line and assign it a status with a `backing` or `note`.
3. Build all marketing/landing/footer copy from `renderable(CLAIMS)` — never hardcode an assertion
   that isn't in the register.
4. Keep the register as the single source of truth: a new claim is added here first (usually as
   `required` or `inProgress`) and promoted only when proven.
