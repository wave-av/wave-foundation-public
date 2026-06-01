# Identity + Money — Phase 2 — Linking (KYC + Multi-Credential)

Phase 1 gave every actor a canonical `public.user_profiles` row + scope grammar + actor chain + audit envelope. **Phase 2 attaches real-world identity** (dual KYC: Stripe Identity + Bridge) and **multi-credential linking** (passkey OR wallet OR federated OIDC, all resolving to one user) — the bridge that lets Phase 3 (spend authority) make charge-against-rail decisions.

## What ships

| Migration | Provides |
|-----------|----------|
| [`006_user_credentials.sql`](./migrations/006_user_credentials.sql) | `public.user_credentials` (passkey / wallet_evm / wallet_sol / oidc_external) + RLS + FK to Phase 1's reserved `primary_credential_id` |
| [`007_kyc_records.sql`](./migrations/007_kyc_records.sql) | `public.kyc_records` + `public.current_kyc` view + `public.current_kyc_level(uuid)` helper |
| [`008_identity_links_history.sql`](./migrations/008_identity_links_history.sql) | `public.identity_links` — append-only history of every link/unlink/KYC event |
| [`009_credential_revocation_guard.sql`](./migrations/009_credential_revocation_guard.sql) | Triggers preventing last-credential disable/delete (anti-lockout) |

## The design promises Phase 2 keeps

1. **One canonical user, N credentials.** Same `user_profiles.id` reachable via Passkey, EVM wallet, Solana wallet, or federated OIDC. Adding/removing credentials never re-creates the profile.
2. **Dual-source KYC.** Stripe Identity for document + selfie; Bridge for fiat ↔ crypto on/off-ramps. `current_kyc_level` returns the max across providers — Phase 3 reads this for spend-authority decisions.
3. **History is the source of truth.** `identity_links` is append-only; the current-state view (`current_kyc`) projects from it. Phase 4 unified audit reads the history directly.
4. **No lockout.** `guard_last_credential` trigger refuses to disable or delete the last active credential. Account closure goes through `user_profiles.disabled_at` instead.

## Apply

```bash
for m in .foundation/frameworks/identity-money/phase-2/migrations/*.sql; do
  supabase db push --linked --include "$m"
done

# verify (offline, foundation-side):
bash .foundation/scripts/check-identity-schema.sh --offline --phase 2

# verify against a real project:
SUPABASE_URL=https://<project-ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
bash .foundation/scripts/check-identity-schema.sh --phase 2
```

## What Phase 2 does NOT do

- **Phase 2.1** (deferred): federated providers (Google / Apple SSO). Not needed for "WAVE-native" identity; will ship when first enterprise customer needs SSO.
- **Phase 2 doesn't issue tokens.** Phase 1 owns token issuance via Supabase Auth + dispatch tokenless OIDC. Phase 2 is purely the linking-record layer.
- **Phase 2 doesn't charge anything.** Spend authority + rail routing is Phase 3.

## Cross-references

- [`../phase-1/README.md`](../phase-1/README.md) — primitives Phase 2 builds on
- [`docs/superpowers/specs/2026-05-29-phase-2-identity-linking-design.md`](../../../docs/superpowers/specs/2026-05-29-phase-2-identity-linking-design.md) — full design
- [`docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md`](../../../docs/superpowers/specs/2026-05-28-phase-3-payment-identity-design.md) — what Phase 2 unlocks
- [`rules/identity-policy.md`](../../../rules/identity-policy.md) — agent-vs-human routing (rules 7, 11)
