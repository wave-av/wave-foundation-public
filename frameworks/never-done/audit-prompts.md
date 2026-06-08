# Audit prompts (posted on every closing PR)

Copy this checklist into a Linear issue / GitHub issue / planning doc when
follow-ups are worth tracking. Reply on the PR with the list of filed
follow-ups OR "no follow-ups identified after audit." Both are valid.

---

### Closure audit — invitation to flag follow-ups

The "Never-Done" rule (`rules/never-done.md`) treats every closure as
an invitation, not an exit. Spend 60 seconds on each prompt below; file
issues for anything that surfaces.

- [ ] **Intent** — did this change actually deliver the intent stated in the closed issue? If partial, what's left, and is that left tracked anywhere?
- [ ] **Regressions** — what could break that nobody tested? Are there code paths now reached more often (or never) that should be validated?
- [ ] **New affordances** — what becomes possible because this landed? Some affordances are valuable (file as features). Some are risky (file as audits or guards).
- [ ] **Deferred / hand-waved** — was anything skipped, stubbed, TODO'd, or "we'll do this later"? File those NOW while the context is fresh.
- [ ] **Consumers** — who/what depends on the surface this PR changed? Have all consumers been notified / verified compatible?
- [ ] **Re-audit cadence** — when should this be looked at again? 1 week (high-risk infra)? 1 release? 1 quarter? File a scheduled audit if cadence is non-trivial.
- [ ] **Operational follow-up** — does this need monitoring, alerting, runbook updates, or on-call coverage that doesn't exist yet?
- [ ] **Doc drift** — does any doc, README, schema, or registry now misrepresent reality because of this change?

### Output

Choose one and reply on the PR:

**Option A — follow-ups filed:**
> Follow-ups: WAVE-NNNN (regression test for X), WAVE-NNNN (new feature flag because Y), …

**Option B — none identified:**
> No follow-ups identified after audit.

Either is fine. The framework is advisory: it doesn't block merging.
The goal is to make the audit moment **visible**, not gated.
