# Wave Execution Methodology

The **build pattern** wave-foundation uses on itself and that consumers inherit. It's not a "style" — it's the gate-able process every multi-PR batch goes through.

## The five steps

### 1. Propose

Surface 3–7 candidate units of work with WHY each matters. Each candidate is:

- A concrete deliverable (PR / commit / artifact)
- Tied to a current foundation gap or external signal (gate finding, user feedback, env-scan, PR-review)
- Sized to land in ~one session

Output: a numbered list of candidate PRs with a one-line pitch each. **Stop and confirm before atomizing** — confirming the scope is cheaper than re-graphing after.

### 2. Atomize

Each accepted candidate becomes a tracked task (`TaskCreate`). Required fields:

- `subject` — imperative form, 5–8 words
- `description` — concrete deliverables, files touched, and the gate(s) it enables
- `activeForm` — present-continuous (shown in spinner during in_progress)

No tasks are created for "investigation" or "research" alone — those collapse into the deliverable's description.

### 3. Dependency-graph

Mark every `blockedBy` relationship with `TaskUpdate addBlockedBy`. Two questions per pair:

- *Can task B's PR be opened before task A's PR merges?* If no → B blockedBy A.
- *Does task B need an artifact (file, script, gate) that A creates?* If yes → B blockedBy A.

Don't over-graph. If two tasks are independent and both ready, they go in the same wave and ship in parallel.

### 4. Wave-execute

A **wave** is the set of tasks with no remaining open blockers. Execute one wave at a time:

- Mark each task `in_progress` when starting it (not as a batch — one at a time, so the spinner matches reality)
- Open the PR. Wait for the 9 required CI checks to go green. Merge. Mark `completed`.
- Once all tasks in the wave are completed, the next wave's tasks become ready.

**The wave gate**: never start a wave-N+1 task while any wave-N task is still incomplete. This is the methodology's whole-system property — it prevents reviewing a chain of PRs in the wrong order and merging incompatible content.

### 5. Audit

After the final wave lands, run `scripts/dogfood.sh` end-to-end. Any gate that previously didn't exist now must pass (or the batch is incomplete). Any gate that NOW fails because the batch surfaced new content is itself a wave-N+1 task — add it, don't ignore.

## Why this exists as a methodology and not just "good practice"

- **Confirmation gate at step 1 prevents waste** — atomizing a 10-PR batch that the user only wanted 3 of is the most expensive mistake to undo
- **Atomic tasks survive context resets** — the next session (or agent) can pick up at any wave boundary
- **The dependency graph IS the documentation** — readers reconstruct the build order from `blockedBy` edges, not from PR descriptions
- **Parallel waves are explicit** — anything not in a wave with deps to it CAN ship in parallel; the methodology makes that visible instead of accidental
- **The dogfood audit at step 5 catches the failure mode where step 4 silently dropped something** — without it, a missing-gate PR can "land" without actually adding the gate

## Anti-patterns

- ❌ Skipping step 1 ("confirmation") because "it's obvious what to build" — the cost of confirming is one message; the cost of unwinding is hours
- ❌ Atomizing into 30 tasks ("waterfall in disguise") — keep waves wide and shallow, max 7 tasks per wave
- ❌ Marking multiple tasks `in_progress` simultaneously — spinner state should reflect actual reality, not optimistic intent
- ❌ Merging tasks out of dependency order ("just this one because it's ready") — breaks the wave gate, lands incompatible content
- ❌ Treating dogfood audit as optional — without it the build silently regresses

## Cross-references

- `methodology-registry.json` — this method registered alongside the other 20
- `frameworks/improvement-loop/` — uses this methodology for its own self-improvement cycles
- `plugin/skills/plan-to-action/` — automates step 2 (atomization)
- `plugin/skills/wave-execute/` — automates step 4 (wave execution)
- `plugin/skills/plan-audit/` — automates step 5 (audit)

## Tracking record

The current session's task list (`feat/improvement-loop-wired` and onward) is the canonical example: PRs E–K opened with explicit `blockedBy` edges, executed in 3 waves, audited via dogfood at each wave boundary.
