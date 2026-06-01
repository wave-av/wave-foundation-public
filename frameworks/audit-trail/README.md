# Append-Only Audit Trail Pattern

Every WAVE service that records "who did what to which resource" uses this one
shape — the same `audit_events` table the identity-money program is built on
([`frameworks/identity-money/phase-1`](../identity-money/phase-1/) ships the
canonical instance; Phase 4 the query layer; Phase 5 the active monitor). This
framework generalizes it so a service can adopt the audit trail **without** taking
the whole identity-money schema.

## The five invariants

An audit trail is only trustworthy if all five hold. Drop any one and the log
becomes "logging," not an audit trail.

1. **Append-only, enforced at the trigger layer.** RLS alone is not enough — a
   `service_role` or superuser can still `UPDATE`/`DELETE`. A `BEFORE UPDATE OR
   DELETE` trigger that `RAISE EXCEPTION` is the real guarantee.

   ```sql
   CREATE OR REPLACE FUNCTION public.audit_block_mutation() RETURNS trigger
   LANGUAGE plpgsql AS $$
   BEGIN
     RAISE EXCEPTION '% is append-only (op=%)', TG_TABLE_NAME, TG_OP
       USING ERRCODE = 'check_violation';
   END $$;
   ```

2. **Actor is a chain, not a scalar.** Record `actor_chain uuid[]` (top-to-leaf:
   orchestrator → agent → human), not a single `user_id`. Delegated and automated
   actions have ≥2 actors; a scalar throws away who-vouched-for-whom. `CHECK
   (cardinality(actor_chain) >= 1)`. Query membership with `actor_chain @> ARRAY[x]`.

3. **Tenant-bound with `ON DELETE RESTRICT`.** Every row carries `tenant_id`; the FK
   restricts so an audit row can never be orphaned by a tenant delete. RLS scopes
   reads to tenant owners/admins.

4. **Before + after as `jsonb`.** Capture `before`/`after` state (NULL on
   create/delete respectively) so the row is self-describing — a reader reconstructs
   the change without joining to mutable tables that may have moved on.

5. **Authorization context on the row.** Record the `scope_used` (and DPoP
   thumbprint / request_id / trace_id where available) so the log answers "under what
   grant?" not just "what changed?".

## Minimal adoption (no identity-money schema)

A service that just needs the trail copies this skeleton (the trimmed-down Phase-1
`005_audit_envelope.sql`):

```sql
CREATE TABLE IF NOT EXISTS public.audit_events (
  event_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ts          timestamptz NOT NULL DEFAULT now(),
  actor_chain uuid[] NOT NULL,
  action      text NOT NULL,            -- dotted: "billing.invoice.voided"
  resource    text NOT NULL,            -- "<table>/<id>" or "<service>:<op>"
  before      jsonb,
  after       jsonb,
  scope_used  text,
  tenant_id   uuid NOT NULL,            -- add the FK if you have a tenants table
  request_id  uuid,
  trace_id    uuid,
  CHECK (cardinality(actor_chain) >= 1)
);
CREATE INDEX IF NOT EXISTS audit_events_tenant_ts_idx ON public.audit_events(tenant_id, ts DESC);
CREATE INDEX IF NOT EXISTS audit_events_actor_idx     ON public.audit_events USING gin(actor_chain);
CREATE INDEX IF NOT EXISTS audit_events_action_idx    ON public.audit_events(action);
-- + the append-only trigger above + RLS.
```

For the full thing (forensic query functions, retention, the active anomaly monitor)
adopt [`identity-money`](../identity-money/) instead of copying — this framework is
for services that want the **trail only**.

## Action naming

`<domain>.<noun>.<verb-past-tense>` — dotted, lowercase, past tense (the event
already happened). `billing.invoice.voided`, `agent.token_exchange.granted`,
`spend.allowed`. The dotted prefix is what Phase-5 anomaly rules `LIKE`-match
(`spend.%`), so keep the domain segment stable.

## Anti-patterns

- ❌ Mutating audit rows to "correct" them — append a compensating event instead.
- ❌ A scalar `user_id` for actor (loses delegation chains).
- ❌ Logging the credential/secret in `before`/`after` — log plan/status/`email_domain`,
  never the `wv_*` key or token (same rule as `frameworks/observability`).
- ❌ Soft-deleting via an `is_deleted` column on the audit table — append-only means
  no deletes, soft or hard.
- ❌ Relying on RLS for immutability — add the trigger.

## Relation to other frameworks

- [`identity-money`](../identity-money/) — the canonical instance + query/monitor layers.
- [`observability`](../observability/) — audit is the durable record; observability is
  the real-time signal. Don't conflate: a Sentry event is not an audit row.
- [`compliance`](../compliance/) — SOC2 CC7/CC8 lean on this trail; the append-only
  trigger is the control evidence.
