# Identity + Money — Phase 3 — Payment & Spend Authority

Phase 2 attached real-world identity (KYC + multi-credential linking) to the canonical user. **Phase 3 attaches money**: N payment sources per user (Stripe / Bridge / Tempo MPP / self-custody wallet), explicit `spend_authorities` (cap × window), and `spend_delegations` (orchestrator → child agent). Together they make Phase-3 scope tokens like `wsc:pay:up_to_5_usd` enforceable end-to-end.

## What ships

| Migration | Provides |
|-----------|----------|
| [`010_payment_sources.sql`](./migrations/010_payment_sources.sql) | `public.user_payment_sources` (5 rails) + partial uniques per rail + wires Phase-1's reserved `primary_payment_source_id` FK |
| [`011_spend_authorities.sql`](./migrations/011_spend_authorities.sql) | `public.spend_authorities` + `has_spend_authority()` matcher + `spend_uncapped_eligible()` (KYC level >= 2 gate for `wsc:pay:any`) |
| [`012_spend_delegations.sql`](./migrations/012_spend_delegations.sql) | `public.spend_delegations` + `has_delegated_spend()` matcher |
| [`013_payment_credential_link.sql`](./migrations/013_payment_credential_link.sql) | Trigger auto-linking Phase-2 wallet credential → Phase-3 self-custody payment source by address match |

## Five rails

| Rail | source_type | Use case |
|------|-------------|----------|
| Stripe (card/bank) | `stripe_card`, `stripe_bank` | Humans pay; humans pay for agents |
| Bridge | `bridge_virtual_account` | Fiat ↔ stablecoin on/off-ramp |
| Tempo MPP | `tempo_mpp_wallet` | Agent-native payments on Stripe's stablecoin L1 |
| Self-custody | `self_custody_wallet` | Direct on-chain settlement (same address as Phase-2 auth credential, auto-linked) |

## Scope grammar extensions (`pay` verb)

| Scope | Maps to |
|-------|---------|
| `wsc:pay:up_to_5_usd` | `spend_authorities.cap_amount = 500 cents, window='per_request'` |
| `wsc:pay:up_to_500_usd` | `spend_authorities.cap_amount = 50_000 cents, window='per_request'` |
| `wsc:pay:any` | `cap_amount IS NULL` — gated by `spend_uncapped_eligible()` (KYC level >= 2) |
| `tempo:pay:agent_native` | routed via `tempo_mpp_wallet` only |

Verbs added to the Phase-1 `auth.has_scope()` function (`pay` is now a valid verb). No function change needed — the grammar is verb-extensible.

## The money rule (recap from Phase 1 §2.4)

Root payer defaults to the actor at the deepest `act` claim (typically the human). An orchestrator paying for sub-agent work overrides via explicit `pay_as` claim, which must be a user the actor holds `wsc:delegate:pay` over (encoded as a `spend_delegations` row here).

## Apply

```bash
for m in .foundation/frameworks/identity-money/phase-3/migrations/*.sql; do
  supabase db push --linked --include "$m"
done

# verify (offline, foundation-side):
bash .foundation/scripts/check-identity-schema.sh --offline --phase 3

# verify against a real project:
SUPABASE_URL=https://<project-ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
bash .foundation/scripts/check-identity-schema.sh --phase 3
```

## What Phase 3 does NOT do

- **Settlement orchestration**: this Phase ships the schema + authority model. The actual charge call (Stripe `paymentIntents.create`, Tempo `pay()`, Bridge `transfer()`) is per-consumer code that READS these tables.
- **Treasury / stablecoin issuance**: Bridge has separate features; not adopted Phase 3.
- **Refund/dispute UI**: Stripe dashboard initially.
- **Phase 4 unified audit query layer**: Phase 4 ships that.

## Cross-references

- [`../phase-1/README.md`](../phase-1/README.md) — actor-chain, scope grammar
- [`../phase-2/README.md`](../phase-2/README.md) — KYC level + wallet credentials (link target)
- [`docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md`](../../../docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md) — full design
- [`rules/identity-policy.md`](../../../rules/identity-policy.md) — payment vs identity rules
- [`scripts/check-spend-authority.sh`](../../../scripts/check-spend-authority.sh) — Phase-T import-scan gate (rail keys never read by agents)
