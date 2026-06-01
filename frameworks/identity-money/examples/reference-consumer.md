# Reference consumer — adopting identity-money end to end

A worked example of a spoke adopting the full identity+money program: apply the
schema, authorize a request with the block-aware gate, record the audit row, and
react to an anomaly finding. Not a runnable app — the **integration points** a real
consumer wires, in order, with the exact foundation calls.

Assumes the foundation is vendored at `.foundation/` (see `CONSUME.md`).

## 1 — Apply the schema

Use the runner; it applies phases 1..5 in order and is idempotent:

```bash
bash .foundation/scripts/apply-identity-migrations.sh --db-url "$SUPABASE_DB_URL" --phase 5
# verify:
bash .foundation/scripts/check-identity-schema.sh \
  --supabase-url "$SUPABASE_URL" --service-role "$SERVICE_ROLE" --phase 5
```

Phase 5's `021_pg_cron_install.sql` self-skips if `pg_cron` is absent; enable the
extension first if you want the anomaly evaluator scheduled (else call
`public.evaluate_anomaly_rules()` from your own scheduler).

## 2 — Authorize on the block-aware gate

A consumer must NOT hand-roll scope checks. Every protected action calls
`auth.actor_can(actor, claim_scopes, required)` — `has_scope` AND not anomaly-blocked.
The IMMUTABLE `auth.has_scope` is for pure RLS policies; **request paths use
`actor_can`** so Phase-5 enforcement is honored:

```sql
-- in an RLS policy on a protected table, or a SECURITY DEFINER RPC the spoke calls:
CREATE POLICY pmsrc_spend ON public.user_payment_sources
  FOR UPDATE USING (
    auth.actor_can(auth.uid(), current_setting('request.jwt.claims.scopes', true)::text[],
                   'billing:spend:any')
  );
```

```ts
// or in app code before a spend (the worker holds the actor uuid + scopes from the JWT):
const { data: allowed } = await db.rpc("actor_can", {
  actor_id: actorId, claim_scopes: scopes, required: "billing:spend:any",
});
if (!allowed) return deny(403, "blocked or unauthorized");
```

## 3 — Record the state-changing op

Every mutation appends one `audit_events` row (the trail Phase 4 queries + Phase 5
watches). Action names are dotted, past-tense — the prefix is what anomaly rules
`LIKE`-match (`spend.%`):

```ts
await db.from("audit_events").insert({
  action: "spend.allowed",                 // dotted, past tense
  actor_chain: [orchestratorId, agentId, actorId].filter(Boolean), // top→leaf
  resource: `pmsrc/${paymentSourceId}`,
  scope_used: "billing:spend:any",
  after: { amount: cents },                // plan/amount, NEVER the credential/secret
  tenant_id: tenantId,
});
```

This single row is what makes the actor visible to detection — skip it and Phase 5
can't see the action.

## 4 — React to an anomaly finding

The evaluator writes `anomaly_findings`; enforcement (block/auto-revoke) already
fired for `block_next`/`auto_revoke_scope` rules. The consumer's responsibilities:

- **Surface alerts** — run the poller over `public.anomaly_findings_to_alert`, route
  per `.foundation/frameworks/observability/anomaly-routes.yml`, then
  `select public.mark_anomaly_alerted(finding_id)`. (Verify the path with
  `frameworks/observability/sync-verification.md`.)
- **Handle blocks gracefully** — a blocked actor's `actor_can` returns false; return a
  clear 403 and a support path, not a stack trace.
- **Triage** — follow `frameworks/identity-money/phase-5/anomaly-incident-playbook.md`
  (true-positive vs false-positive, the reversible un-block/re-enable sequence).

## The contract, in one line

Apply the migrations · authorize with `actor_can` (not bare `has_scope`) · append an
`audit_events` row per mutation · let Phase 5 detect/alert/enforce · triage findings
with the playbook. Everything else (schema, evaluator, rules, routing) is the
foundation's — the consumer wires these four touch-points and consumes the rest.

## See also

- `frameworks/identity-money/phase-{1..5}/README.md` — per-phase detail
- `scripts/apply-identity-migrations.sh` · `scripts/check-identity-schema.sh`
- `docs/diagrams/er/identity-money-schema.md` — the schema picture
- `frameworks/identity-money/phase-5/anomaly-incident-playbook.md` — incident response
