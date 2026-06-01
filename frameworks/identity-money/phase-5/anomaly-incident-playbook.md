# Anomaly Finding → Incident Playbook

The on-call runbook for when a Phase-5 anomaly finding fires. Bridges
[Phase 5](./README.md) (detect → alert) to
[`frameworks/incident-response`](../../incident-response/) (respond). Use the
[runbook contract](../../incident-response/runbook-template.md); this is the
identity-money-specific instance.

## What triggers an incident

A row in `public.anomaly_findings`. How it reaches you depends on severity, per
[`frameworks/observability/anomaly-routes.yml`](../../observability/anomaly-routes.yml):

| Finding severity | Routed to | Incident sev (map) |
|------------------|-----------|--------------------|
| `info` | nothing (recorded only) | — |
| `warning` | Sentry | P2 (next business day) |
| `blocking` | Sentry + Linear (SECURITY) + Slack `#incidents-security` | **P1** (< 30min ack) |

A `blocking` finding with a `auto_revoke_scope` rule means **enforcement already
happened** — credentials were disabled and the actor blocked before you were
paged. Your job is to confirm or reverse, not to stop a live attack.

## Triage (first 30 minutes)

1. **Pull the finding + evidence:**

   ```sql
   SELECT f.*, r.name, r.action, r.match_action, r.threshold, r.aggregate
   FROM public.anomaly_findings f JOIN public.anomaly_rules r ON r.id = f.rule_id
   WHERE f.id = '<finding_id>';
   -- evidence holds a capped sample of the audit_events rows that tripped it
   SELECT f.evidence FROM public.anomaly_findings f WHERE f.id = '<finding_id>';
   ```

2. **Confirm or refute.** Is the `measured_value` a real attack or legitimate
   burst (a batch job, a migration, a known large customer)? Cross-check the actor
   + tenant against expected behavior. The `actor_chain` leaf is the principal;
   `find_actor_history` (Phase 4) gives the full picture:

   ```sql
   SELECT * FROM audit.find_actor_history('<actor>', now() - interval '24 hours');
   ```

3. **Check what enforcement fired** (for `block_next` / `auto_revoke_scope`):

   ```sql
   SELECT * FROM public.actor_blocks WHERE actor_id = '<actor>';          -- blocked?
   SELECT id, kind, disabled_at FROM public.user_credentials WHERE user_id = '<actor>';
   SELECT * FROM public.identity_links WHERE event = 'credential_auto_revoked'
     AND user_id = '<actor>' ORDER BY ts DESC;
   ```

## Resolution paths

### True positive (real abuse)

- Enforcement already applied (block/revoke). Confirm the block TTL is adequate; an
  admin can extend `actor_blocks.blocked_until` or, for a cross-tenant repeat,
  promote to a Phase-6 global block (when shipped).
- File the post-mortem ([template](../../incident-response/post-mortem-template.md)):
  what scope/instrument was abused, whether the rule threshold was right, whether a
  new rule is warranted.
- Communicate to the affected legitimate parties if the actor's account was a
  compromised real user (vs a pure attacker).

### False positive (legitimate burst)

- Mark the finding resolved with a note (RLS allows owner/admin):

  ```sql
  UPDATE public.anomaly_findings
  SET resolved_at = now(), resolution_note = 'FP: <reason>' WHERE id = '<finding_id>';
  ```

- **Reverse any enforcement** (this is the reversible-by-admin path Phase 5.3
  promises):

  ```sql
  -- lift the block
  DELETE FROM public.actor_blocks WHERE actor_id = '<actor>';
  -- re-enable the auto-revoked credentials
  UPDATE public.user_credentials SET disabled_at = NULL
   WHERE user_id = '<actor>' AND disabled_at IS NOT NULL;
  -- log the reversal (accountability — Phase 5 spec Q3 default)
  INSERT INTO public.identity_links (user_id, credential_id, event, performed_by, metadata)
  SELECT '<actor>', id, 'credential_linked', '<admin_user_id>',
         jsonb_build_object('reason', 'reversal of FP finding <finding_id>')
  FROM public.user_credentials WHERE user_id = '<actor>';
  ```

- **Tune the rule** so the same legitimate pattern doesn't re-fire: raise the
  `threshold`, narrow `match_action`, or (per the Phase 5 spec Q4 default) add a
  finding exemption when that ships. Don't just resolve-and-move-on — a rule that
  cries wolf gets ignored.

## Escalation

Follow the [severity ladder](../../incident-response/README.md#severity-ladder).
A `blocking` finding is **P1** by default (security event under investigation). If
the abuse is customer-impacting or spans many tenants → **P0**, page
`security-oncall`, and treat the cross-tenant angle as Phase-6 scope.

## Anti-patterns

- ❌ Resolving a finding without deciding TP/FP (you lose the signal either way).
- ❌ Reversing an auto-revoke without logging the reversal (breaks the audit chain).
- ❌ Repeatedly resolving the same FP instead of tuning the rule.
- ❌ Treating an `info`/`warning` page as P1 (alert fatigue) — honor the routing map.
