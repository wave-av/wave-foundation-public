# Done Is A Trigger (methodology view of the Never-Done rule)

> **Canonical statement: [`rules/never-done.md`](../../rules/never-done.md).**
> This file is the *methodology-catalog* view — it places the Never-Done rule in the
> methodology registry/scoring system and gives agents the concrete audit checklist. It
> does **not** restate or override the rule. If this doc and the rule ever disagree, the
> rule wins.

**"Nothing is ever done. If you think something is done, that's the signal to audit it."**

The single most dangerous state in this system is the belief that a unit of work is
*finished*. "Done" is where attention leaves, where the next reviewer assumes coverage,
where latent edge-cases hide. So we treat **done as a trigger, not a terminal**: a closure
event (task done, PR merged, issue closed, release shipped) is an *invitation to file
follow-ups*, not an exit.

This methodology is the human-judgment complement to the
[improvement loop](../improvement-loop/README.md) (which auto-feeds *gate findings* forward)
and the standing, every-completion form of Wave Execution's 5th step
([`wave-execution.md`](./wave-execution.md) → *audit*) — fired at every close, not just
end-of-wave.

## Enforcement (it is NON-blocking by design)

Per the founder framing in the rule, this **does not block merges** — blocking adds ritual
friction that real work routes around. It is surfaced, not gated-hard:

- [`frameworks/never-done/`](../never-done/) — the automation: `generate-comment.sh` /
  `post-comment.sh` + [`.github/workflows/never-done.yml`](../../.github/workflows/never-done.yml)
  post the audit-prompts comment on any PR that claims to close something.
- `frameworks/gates/registry.yaml` — the **advisory** `never-done` gate entry.

There is no "ratchet to required" plan; advisory is the intended terminal state.

## The DONE→AUDIT pass (the agent's checklist)

These five lenses are the concrete cut an agent runs over its own work — an elaboration of
the rule's question list and [`frameworks/never-done/audit-prompts.md`](../never-done/audit-prompts.md).
Each yields either *nothing material* (record why it holds) or a finding (file a follow-up;
ship the safe ones now):

1. **Edge cases / failure modes** — empty input, missing prereq, auth 403, race, retry,
   cold start, a freshly-provisioned consumer. Does it fail *closed and loud*, or *open and
   silent*? (Fail-open is worse than fail-closed — see Error Handling Completeness, #7.)
2. **Adjacent gaps** — what did this work *expose* that it didn't *cover*? (The label the
   script applies but the provisioner never created. The stage hardened on one runner but
   not the other.)
3. **Hostile review** — what would a prompt-injection, a hostile contributor, or a skeptical
   security reviewer find here? Assume they will. (Leans on Security Audit, #6.)
4. **Uplevel** — the cheapest change that makes this *better*, not just *present*:
   observability, an actionable error in place of a cryptic one, a test for the path you
   only reasoned about, a doc the next operator needs.
5. **Completeness** — what's still assumed rather than verified? A runtime test not run, a
   claim not proven, a file not read. (Pairs with the Ambiguity Gate: ambiguity → STOP +
   research; done → AUDIT + uplevel.)

## The agent reporting contract

Identical to the rule: an agent that reports "task complete" / "issue closed" MUST include
**either** the follow-ups it filed (with issue/task IDs) **or** an explicit *"no follow-ups
identified after audit."* Never a bare `"done"` — and never `"done, I'm blocked on you"`
without the audit first.

## Cross-references

- [`rules/never-done.md`](../../rules/never-done.md) — **canonical** rule
- [`../never-done/`](../never-done/) — the audit-on-closure automation + advisory gate
- [`wave-execution.md`](./wave-execution.md) — the *audit* step this generalizes
- [`../improvement-loop/README.md`](../improvement-loop/README.md) — the automated complement
- [`README.md`](./README.md#done-is-a-trigger) — catalog entry
