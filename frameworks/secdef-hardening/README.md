# SECURITY DEFINER Hardening

5-tier risk classification + iterative-soak playbook for the ~365 SECURITY DEFINER
functions across WAVE Supabase staging (mirrored in prod).

## Why this matters

A `SECURITY DEFINER` function runs with its creator's privileges (typically `postgres`
with `bypassrls`). If callable by `anon` or `authenticated` (default Postgres grant
via `PUBLIC` inheritance) AND lacks an internal auth check, **every caller bypasses
RLS** — single-tenant breach surface.

## Risk tiers (from `inventory.sql`)

| Tier | Criteria | Action |
|------|----------|--------|
| **1 NO_GUARD_exposed** | anon/auth EXECUTE + no `auth.uid()` + no role gate + no RAISE | Hardest. Either gate body OR revoke EXECUTE to service_role-only. |
| 2 has_raise | has `RAISE EXCEPTION` but no auth check | Verify the RAISE actually gates — could be just an error path. |
| 3 role_gate | references `service_role` or `current_setting` | Already partial — verify gate covers all branches. |
| 4 has_auth_check | references `auth.uid()` / `auth.role()` | Lowest risk. Spot-check the predicate isn't trivially bypassable. |
| 5 service_role_only | EXECUTE NOT granted to anon/auth | Lowest risk. No action. |

## WAVE staging measurement (2026-06-04)

```
1_NO_GUARD_exposed
  public stable    58       <-- read-side leak surface (B2)
  public volatile  251      <-- write/admin leak surface (B3)
  stripe_wave v      4
  ─────────────────────
  subtotal         313      <-- TIER-1 EXPOSURE

2_has_raise         19
3_role_gate          3
4_has_auth_check    29
5_service_role_only  1
─────────────────────
TOTAL              365
```

## Mitigation strategy by tier (per [[wave-for-platforms-mega-plan-2026-06-03]] Phase B)

### B2 — null-uid early-out on Tier-1 stable (58 funcs)
For READ-side (`provolatile = 's'`) Tier-1 functions:
```sql
-- prepend at function body top:
IF auth.uid() IS NULL THEN
  RETURN; -- or RETURN NULL/RETURN QUERY SELECT WHERE false;
END IF;
```
This blocks anon callers cleanly without breaking authenticated flows.
**Risk**: low (only affects anon). **Reversible**: yes (drop the prepended block).

### B3 — raise-exception on Tier-1 volatile (251 funcs)
For WRITE-side Tier-1 functions:
```sql
-- prepend at function body top:
IF auth.uid() IS NULL THEN
  RAISE EXCEPTION 'unauthorized: % requires authentication', tg_argv[0];
END IF;
```
**Risk**: medium — breaks callers that intentionally invoke without an auth context
(e.g. CRON-driven SECDEF jobs running via `pg_cron` as `postgres` role; verify each).
**Reversible**: yes.

### B4 — drop SECDEF where not needed
Candidates: functions that don't write to RLS'd tables or that only call other
SECDEFs. Switching to `SECURITY INVOKER` is the cleanest fix.
**Risk**: high if the function was relied on for RLS bypass — every consumer must
have the underlying-table privileges directly. Test extensively.

### B5 — merge multiple_permissive RLS policies (top-10 worst tables)
Out-of-scope for SECDEF; tracked separately as a `pg_policies` performance + clarity
fix. Multiple permissive policies on the same operation evaluate as a UNION — slow
and easy to misread.

### B6 — always-true RLS risky-subset review
Out-of-scope for SECDEF; subset of `USING (true)` policies that need tightening.

## Execution recipe

For each tier-1 batch (B2 read-side first, then B3 write-side):

1. **Carve a batch** — start with 5-10 functions, never the full set.
2. **Codify the fix** as a versioned migration in `supabase/migrations/<ts>_secdef_b2_batch_<n>.sql`.
3. **Apply via MCP `apply_migration`** on staging.
4. **Run advisors**: `supabase db advisors` (CLI ≥2.81.3) — verify no new findings.
5. **Soak 24h** — watch for callers breaking (alerts, Sentry, dispatch logs).
6. **Promote to prod** via `rules/supabase-prod-guard.md` operator flow.
7. **Update this README's checked-off batches** + Linear ticket.

## Tooling

- `inventory.sql` — re-runnable tier classification query
- (planned) `materialize-batch.sql` — generate `CREATE OR REPLACE FUNCTION` patches
  for a tier+volatility cohort
- (planned) `verify-callers.sh` — grep WSC + dispatch + foundation for `rpc('<fname>')`
  callers before flipping the gate

## Pre-flight checklist (operator)

Before applying ANY tier-1 batch to prod:

- [ ] Staging soak ≥24h with no incidents
- [ ] WSC `apps/web` smoke flows pass (auth → dashboard → settings)
- [ ] No new Supabase advisor findings vs baseline
- [ ] Sentry quiet on `42501` (insufficient privilege) errors
- [ ] Dispatch `/x402/verify` continues settling
- [ ] Backup snapshot ID captured

## Tasks

- B1 (this PR): inventory + tier classification + runbook ✅
- B2 / #210: null-uid early-out batch — 58 Tier-1 stable funcs in 10-func batches
- B3 / #211: raise-exception on 251 Tier-1 volatile funcs (after B2 lands)
- B4 / #212: drop SECDEF where not needed (deferred — requires per-function dependency map)
- B5 / #213: multiple_permissive merge (separate from SECDEF)
- B6 / #214: always-true RLS review (separate from SECDEF)

## Refs

- Memory: [[wave-for-platforms-mega-plan-2026-06-03]] Phase B
- Memory: [[wave-clearair-adr009-audit-2026-06-02]] §audit-scanner — the dispatch SECDEF audit
- Rule: `rules/supabase-prod-guard.md`
- Supabase docs: `https://supabase.com/docs/guides/security/product-security.md` §SECURITY DEFINER
