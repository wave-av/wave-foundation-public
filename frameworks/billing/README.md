# WAVE Billing & Settlement Contract

> How a product's `pricing.yaml` (the *what*) becomes real money collected across providers (the *how*),
> identically in **code, Stripe, Metronome, and Supabase** — for humans and autonomous agents, on every rail.
> The companion to [`frameworks/pricing`](../pricing/README.md): pricing answers *what does it cost*; this
> answers *how is it metered, settled, and proven correct*. **Code is authoritative; providers are mirrors.**

## The one rule everything else protects

**Code is the source of truth. The catalog is pushed OUT to providers; reconcile gates catch drift.**

A product never hand-edits a Stripe price or a Metronome rate-card in a dashboard. It declares its model in
`pricing.yaml` + a `billing.config.yaml`, and a deterministic push job provisions every provider from that
model. A CI drift gate then asserts `code == live` on every PR. This is the only way one model stays
identical across four systems that each have their own console where someone could "just fix it."

## The reference implementation

`wave-av/wave-dispatch` is the proven reference — built, tested, and **applied live** (2026-05-31):

| Concern | Reference artifact (in wave-dispatch) |
|---|---|
| Provider seam (dual-write) | `edge-router/billing/registry.ts` + `*-provider.ts` |
| Stripe-native provisioner | `scripts/setup_stripe_native.py` |
| Metronome bridge provisioner | `scripts/setup_metronome_bridge.py` |
| Code→providers push job | `scripts/push_billing.py` |
| Reconcile drift gate (CI) | `scripts/reconcile_billing.py` |
| Real-invoice e2e (margin) | `scripts/e2e_billing_invoice.py` |
| Supabase audit mirror | `edge-router/billing/supabase-mirror.ts` + `supabase/migrations/0001_dispatch_billing.sql` |

Generalize from these; do not re-derive them.

## THE CENTS INVARIANT (read this twice)

This is the single highest-severity rule in the standard. Getting it wrong silently **under-bills by 100×**.

- Every meter event carries `value = amount_usd` in **DOLLARS**. The meter SUMs `value`.
- The provider price is a **passthrough**: it charges **100 cents per unit-of-summed-value**, i.e.
  `invoice_cents = Σ(amount_usd) × 100` — the dollar sum re-expressed in cents.
  - **Stripe:** metered Price `unit_amount_decimal = "100"` (cents/unit). `billing_scheme=per_unit`,
    `recurring.usage_type=metered`, `recurring.meter=<meter id>`.
  - **Metronome:** the only USD fiat type is **`USD (cents)`**. Rate-card rates are stored in **CENTS** =
    code-dollars × 100 (e.g. `decisions` $0.0001 → `0.01`¢; passthrough meter → `100`¢/unit). Events still
    carry `amount_usd` in dollars.
- **Never store dollars where a provider expects cents.** Dollars-as-cents on Stripe `unit_amount`, or
  cents-as-dollars on a Metronome rate, is a silent 100× error. The reconcile gate asserts the literal `100`
  passthrough and the per-meter cents rate on every PR precisely to fail this class.
- Round **half-up** to cents (mirror the provider), not banker's rounding. `round_half_up(1.2325 × 100) = 123`.

## Dual-write topology

`emitMeter()` is the one call sites use. It mints **one idempotency key per billable decision** (a UUID) and
fans that *same* key to every sink, so dedup and cross-store reconciliation are trivial:

```
emitMeter(decision)
  → ledger        (ALWAYS — the internal savings/usage ledger; never gated)
  → authoritative (the invoicing-of-record provider; 0 or 1)
  → shadows[]     (rating oracles that DON'T collect — collect=false)
  → mirror        (Supabase audit/analytics — the third system of record)
```

- **Authoritative** = the one provider that issues the collectible invoice. Recommended default: **Stripe-native**.
- **Shadow** = a provider that rates the same usage but never collects (`collect=false`), so you can compare
  invoices and flip authority with a config change, not a migration. Recommended: **Metronome** as shadow
  (Stripe acquired Metronome; APIs aren't merged; staying dual-ready hedges the unknown winner).
- **Mirror** = Supabase `dispatch.usage_events` (PK = the idempotency key, `merge-duplicates` upsert so each
  provider's emit merges its own `*_ref` into one row). Audit/analytics only — it never prices.
- Flip authority with `BILLING_AUTHORITATIVE` / `BILLING_SHADOW` env vars. **Default `BILLING_AUTHORITATIVE=none`
  = ledger-only, behavior unchanged** — billing stays dark until a deliberate, customer-ready go-live.

### The provider-registration footgun (proven in dispatch B5)

Providers self-register **only when their module is imported**. If nothing imports them, `emitMeter` silently
no-ops in production while tests (which import providers directly) stay green. **Require side-effect imports at
the worker entry point AND a registration-guard test** asserting `providersFor({AUTHORITATIVE:'stripe',
SHADOW:'metronome'})` actually resolves both. A green test suite is not proof the prod path is wired.

## Org-side connection is the one human step

Everything is API-creatable EXCEPT the provider's org-level connection:

- **Stripe:** account exists; the key (sk_live) is the connection.
- **Metronome:** the org→Stripe OAuth connection is **dashboard/OAuth-only** (the API enum excludes it). It is
  API-*readable* via `listConfiguredBillingProviders → delivery_method_id` (the one proof the human step
  happened). Prod connection = `solutions@metronome.com`; sandbox auto-maps to Stripe TEST.

Gate any prod-Metronome-billing-of-record behind that connection + a prod key. Until then Metronome is shadow.

## Wire gotchas (settled empirically — do not relearn)

- **Metronome SUM metric** REQUIRES `property_filters:[{name:"<value key>",exists:true}]` declaring the
  aggregation key, or it 400s.
- Metronome per-customer path is **hyphenated** `/billing-config/stripe` (camelCase route-404s → silent
  `collecting:false`). Binding validates `billing_provider_customer_id` against the connected Stripe account at
  bind-time — the `cus_` must pre-exist (Metronome does not create it).
- **Stripe** `/invoices/upcoming` is deprecated → `POST /invoices/create_preview` with `subscription`.
- Provisioners and the push job are **`--dry-run` by default**; `--apply` writes. Run reconcile after every apply.

## The tri-store, reconciled

| Store | Role | Validated by |
|---|---|---|
| **Code** (`pricing.yaml` + `billing.config.yaml`) | source of truth | `validate-billing.py` + schemas |
| **Stripe** | invoicing-of-record (authoritative) | `reconcile_billing.py` (passthrough = 100) |
| **Metronome** | shadow rating oracle (`collect=false`) | `reconcile_billing.py` (cents rate) |
| **Supabase** | audit/analytics mirror | `dispatch.usage_events` upsert on idempotency key |

A real (test) invoice MUST be asserted against the code model before any go-live — not a dict literal.
`e2e_billing_invoice.py` drives customer → metered subscription → meter events → `create_preview` and asserts
`line_cents == round_half_up(Σ value × 100)`, with both strictly `> 0` (a zero-usage run is an inconclusive
FAIL, never a pass).

## Adopting (consume, don't copy)

1. Add `billing.config.yaml` (the scaffolder ships the template) declaring authoritative/shadow/mirror + the
   passthrough invariant. Keep `pricing.yaml` as the rate source.
2. Vendor `validate-billing.py` via `consume.sh`; it runs at commit time and in the `billing-contract` CI gate.
3. Implement the provider seam from the dispatch reference. Wire side-effect imports + the registration guard.
4. Stand up the reconcile drift gate in CI (auto-skips any provider whose key is absent → green hermetically,
   auto-activates the live arm once the secret is set).
5. Keep `BILLING_AUTHORITATIVE=none` until a customer-ready, founder-approved go-live.

See [`billing-config.schema.json`](./billing-config.schema.json) for the validated config shape and the
`topology_meters` extension in [`../pricing/pricing.schema.json`](../pricing/pricing.schema.json).
