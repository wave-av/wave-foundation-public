# WAVE Pricing & Settlement Standard

> How every WAVE product — dispatch today, SRT/NDI/MoQ/Clips/Edge tomorrow, the next 70 — gets
> priced and paid, for **humans and autonomous agents alike**, across **every rail**. Consumed via a
> per-product `pricing.yaml`, not copied. Canonical meter + settlement registry lives here.

## Why this exists

The live Stripe catalog (mapped 2026-05-29) is **85 products, only 9 priced, 76 empty shells**, with
**two overlapping subscription ladders** (WAVE $19/$49/$149/$599 and dispatch $9/$29/$99) and
**duplicate meters** (`storage_gb`/`wave_storage_gb`, `api_calls`/`wave_api_calls`,
`stream_minutes`/`wave_stream_minutes`). New products keep inventing their own pricing, so the sprawl
compounds. This standard ends that: a product answers five questions in `pricing.yaml` and it is priced,
billable across all rails, and consistent with every other product — no re-architecture.

## Three pillars

| Pillar | Question | Where it's answered |
|--------|----------|---------------------|
| **Pricing** | *What does it cost?* | platform tiers + canonical meters (this doc) |
| **Doors** | *Who pays, and how do they reach it?* | human subscription door + agent x402 door |
| **Settlement** | *How is the money collected/settled?* | the WAVE universal delegate (all rails) |

## Two doors, one meter

Every product is reachable two ways. **They reconcile at the meter/settlement layer — NEVER at the
subscription layer.** This is what lets one model serve humans and agents, who have opposite needs.

```
HUMAN door  → a WAVE platform tier = a basket of MODULE ENTITLEMENTS + QUOTAS (one bill)
AGENT door  → /.well-known/x402   = accountless, per-use, zero onboarding
                        ↓ both decrement ↓
            the same CANONICAL METER  →  TenantLedger (#80)
```

A human broadcaster gets stream-minutes *included* in their tier; an autonomous service hits the same
relay's `/.well-known/x402` and pays per-GB with no account — and **both decrement the same
`stream_minutes`/`bandwidth_gb` meter**. Usage is unified underneath regardless of door.

## Canonical meters (the registry)

The deduped, authoritative set. A product MUST bill one of these — it MUST NOT mint a product-local
twin (that is exactly the `storage_gb` vs `wave_storage_gb` disease).

**The machine-readable source of record is [`meters.json`](./meters.json)** — list price, dearest-backend COGS,
aggregation, and `replaces` aliases for every meter. This table is rendered from it. `validate-meters.py`
(the `meter-registry` CI gate) enforces two invariants against `meters.json`: (1) **margin-safety** — every
`list_price_usd >= cogs_usd` (a unit is never sold below the priciest backend that could serve it), and
(2) **single-source** — the three duplicated meter enums (`pricing.schema.json` `meter` + `topology_meters`,
`billing-config.schema.json` `name`) must equal the registry. **To add or reprice a meter, edit `meters.json`
first** — the schema enums + this table follow, and CI fails any drift or below-COGS price.

Prices + COGS verified against official Cloudflare / AWS / Anthropic / OpenAI pages 2026-06-02 (#89); names
match the executed live Stripe migration (#38, [ADR](../../docs/meter-registry-alignment.md) lives in dispatch).

| Meter | Unit | Aggr | List price | Dearest-backend COGS | Replaces |
|-------|------|------|-----------:|---------------------:|----------|
| `decisions` | routing decision | sum | $0.0001 | ~$0 (BYOK control-plane) | — |
| `storage_gb` | GB-month | last | $0.10 | $0.023 (S3 Std; R2 $0.015) | `wave_storage_gb` |
| `bandwidth_gb` | GB egress | sum | $0.08 | $0.053 (CF Stream @2.5Mbps) | — |
| `compute_minutes` | compute-minute | sum | $0.10 | $0.0415 (Lambda H100 GPU-min) | — |
| `stream_minutes` | delivered-minute | sum | $0.005 | $0.0025 (api.video/IVS) | `wave_stream_minutes` |
| `storage_minutes` | stored-minute-mo | last | $0.01 | $0.005 (CF Stream storage) | `wave_storage_minutes` |
| `ai_tokens` | token | sum | $0.000015 ($15/1M) | $0.00001125 (GPT-5.5 3:1) | `wave_ai_tokens` |
| `voice_synthesis_minutes` | synth-minute | sum | $0.25 | $0.18 (ElevenLabs) | `wave_voice_minutes`, `voice_minutes` |
| `transcription_minutes` | transcribed-minute | sum | $0.015 | $0.0062 (AssemblyAI) | `wave_transcription_minutes` |
| `api_calls` | call | sum | *(unpriced)* | *(unpriced)* | `wave_api_calls` |

`decisions` also carries rate-variants (in `meters.json`): x402 $0.001 (10× gas-covering on-chain per-call),
overage $0.0002 (beyond-quota), premium $0.0005 (dispatch_plus). `ai_tokens` is **passthrough** (Metronome sums
`amount_usd`, rate_cents=100; the per-token price is applied by the emitter). `voice_minutes` is **deprecated** —
use `voice_synthesis_minutes` (the descriptive stem dispatch + the live Stripe meter use).

## Human platform tiers

ONE human pricing page. The ~76 "products" become **module entitlements + quotas on a tier**, not SKUs.

| Tier | USD/mo | Posture |
|------|-------:|---------|
| Starter | $19 | individual / try |
| Launch | $49 | small team |
| Scale | $149 | growth |
| Volume | $599 | high-volume |

(Keep the existing GBP/EUR/CAD/AUD + annual prices on this spine.) Each tier carries module entitlement
flags (`modules.ndi = true`) and per-meter quotas; beyond quota = metered overage at the **canonical rate
from [`meters.json`](./meters.json)** (e.g. `ai_tokens` $15/1M, `voice_synthesis_minutes` $0.25/min,
`storage_gb` $0.10/GB — all margin-safe). Never invent an overage rate; read it from the registry.

**Human footgun — overage MUST default to capped + alert.** A simple human plan defaults to a hard spend
ceiling with 80%/100% in-app alerts. Uncapped overage is opt-in, never the default. "Everything included"
must be honestly bounded.

## Per-product pricing profile (`pricing.yaml`)

Every product/spoke declares this. The scaffolder ships the template; the platform + `/pricing.json`
aggregate it; CI asserts it against `pricing.schema.json` (the same way dispatch's `check-config.sh`
guards drift today).

```yaml
product: dispatch
human_access: standalone      # module | standalone
agent_x402:                   # null if the product cannot serve agents
  unit: decisions
  price_usd: 0.0001           # + dispatch_plus: 0.0005
meter: [decisions]            # canonical meter(s) it bills — MUST exist in the registry
economics: control-plane      # hosted | control-plane
rails: [all-via-wave-delegate]
```

**The classification rule:**

- `human_access: module` — folded into platform tiers as a feature flag + quota (most broadcast /
  creator / infra products: clips, srt, ndi, dante, captions, storage, …). One bill.
- `human_access: standalone` — keeps its own tier ladder (only when economically distinct, e.g.
  dispatch). Reconciles with the platform via the shared meters + a discount link, **not** by folding.
- `economics: hosted` — WAVE runs it and bills consumption; CAN fold into platform meters.
- `economics: control-plane` — BYO infra/keys; WAVE bills only its own service fee and **never sees the
  customer's data** (the dispatch trust wall). MUST stay its own surface — a control-plane product cannot
  share a "we-meter-your-consumption" meter without breaking the trust pitch.

## Settlement: the WAVE universal delegate

**A product names a price. It never integrates a rail. It delegates to WAVE**, which accepts any
supported rail and normalizes to the canonical meter + `TenantLedger`. This is already live
(`settlement_via: WAVE (live delegate)`).

| Rail | What it is | Payer |
|------|-----------|-------|
| `card` | Stripe Checkout / subscriptions | humans (fiat) |
| `x402` | HTTP-402 micropayment, on-chain USDC (Base mainnet) | agents |
| `acp` | Agent Commerce Protocol | agents |
| `mpp` | machine-payment protocol | agents |
| `tempo` | stablecoin payments network | either |
| `bridge` | fiat ↔ USDC orchestration | either |
| `privy` | embedded wallet | humans/agents |
| `cdp` | Coinbase Developer Platform wallet | humans/agents |
| `wallet` | generic crypto wallet | either |

Default `rails: [all-via-wave-delegate]` opts a product into the entire set. Centralizing here means a
new protocol inherits **every rail the day it declares a price** — and the PCI/key/fraud surface lives in
ONE audited place, not 85. Per-rail behavior is the WAVE `/verify` contract (dispatch #123).

## Worked examples

- **dispatch** — `standalone` + `control-plane`; agent x402 `decisions` @ $0.0001. Keeps $9/$29/$99 (map
  the 15k/50k/200k decisions-per-day quotas onto the human tiers, **grandfather** existing buyers 12mo to
  avoid a $9→$19 hike). Trust wall intact: WAVE settles, never sees prompts/keys/inference.
- **SRT / NDI / MoQ** (the case that proves the model) — `module` + `hosted`; human gets included
  `stream_minutes` in their WAVE tier; agent hits the relay's `/.well-known/x402` and pays per
  `bandwidth_gb`; both decrement the same meters. (MoQ relay may also stand alone with $/GB COGS pricing.)
- **A future protocol** — declares the 5 fields, picks a canonical meter (or proposes a new one here),
  and is instantly priceable on both doors across all rails.

## Catalog migration (85 → clean)

1. **Classify every product**: backend + price today → keep; `module` candidate with a backend → fold
   into platform tiers as entitlement+quota; backend-less shell → **archive** (set inactive). Net target:
   1 platform product + dispatch (+ MoQ if/when it ships) + the canonical meters.
2. **Dedup meters** to the registry set; delete the `wave_`-prefixed twins.
3. **Delete the duplicate "Dispatch Pro"** product.
4. **Price-or-delete** the defined-but-unpriced meters (compute / transcription / stream) before any tier
   bundles them.
5. **Grandfather** existing dispatch + WAVE subscribers; migrate live Stripe subscriptions behind a flag.

## What this standard does NOT do (YAGNI)

- It does not mandate per-product Prometheus/metrics pipelines — usage federates through the meters.
- It does not require every product to support every rail *itself* — that is the delegate's job.
- It does not set final quota numbers per tier — those are a product decision recorded alongside, not a
  chassis constant.

## Provenance

Extracted from the live dispatch model (`dispatch.yaml`, `/.well-known/x402`, the #80 ledger, the #123
per-rail `/verify` contract) and the 2026-05-29 full-catalog audit. Dispatch remains the reference
implementation of the agent door + settlement delegate.
