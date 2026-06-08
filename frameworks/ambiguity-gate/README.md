# Ambiguity Gate — stop, research, record, then act

Most wasted work and most cross-agent damage in this estate has come from one failure mode: **acting on
an assumption that turned out wrong** — deleting the wrong sync workflow, editing a repo that was actually
a one-way mirror, assuming a public repo could call a private reusable workflow. The fix is a single,
checkable rule:

> **Ambiguity is a STOP condition. Research against ground truth and record the decision *before* you
> mutate anything.**

This framework codifies that rule so every WAVE surface — human or agent — runs the same gate, and so the
resolution to an ambiguity is recorded once and **inherited**, never re-litigated.

## The 6 trigger conditions

You are in ambiguity — and the gate applies — if **any** of these is true. Be honest; these recur here.

| # | Trigger | The hazard it catches |
|---|---------|-----------------------|
| 1 | **Which of N is canonical?** | Multiple files/repos/branches/configs claim the same role — competing sync workflows, `main` vs `staging`, two status apps, prod vs staging secrets. Pick wrong → edit the dead one. |
| 2 | **Will this be overwritten / is it generated?** | The target may be a sync target, codegen output, or vendored copy. Edit the mirror and the next sync clobbers you. |
| 3 | **Is this config real / live / load-bearing?** | Empty tables, `.disabled` middleware, stub workers, placeholder envs — "fixing" a stub does nothing; trusting a stub as live breaks prod. |
| 4 | **A public ↔ private boundary is involved.** | A private reusable workflow called from a public repo (fails silently); a secret about to land in a public mirror. |
| 5 | **A doc says X but the code / live state says Y** (or two docs conflict). | Stale memory or drift. The map is not the territory — verify the territory. |
| 6 | **The action is hard to reverse.** | delete, rotate, archive, force-push, prod write, branch-protection flip. The cost of being wrong is unbounded. |

If none apply, proceed normally — the gate is not a tax on every change, only on ambiguous ones.

## Reuse first: check `DECISIONS.md`

**Before researching anything, read [`DECISIONS.md`](./DECISIONS.md).** The ambiguity may already be
resolved with evidence. If a matching ADR exists, **inherit its decision** — acting *against* a recorded
ADR without *new* evidence is a bug, not initiative. This is the whole point of recording: the second
agent to hit an ambiguity should pay zero research cost.

`DECISIONS.md` in this repo is the **canonical ADR home** for cross-repo build ambiguities. Project-local
ambiguities can live in a project's own `DECISIONS.md`, but anything that affects more than one repo is
recorded here so every consumer inherits it.

## The gate — 4 ordered steps (do not skip to ACT)

1. **DETECT & NAME** — write the competing interpretations explicitly. *"A: edit `dispatch-edge`
   directly. B: `dispatch-edge` is a one-way sync mirror → edit canonical `wave-dispatch`."* If you cannot
   name **both** sides, you have not understood the ambiguity yet — keep going until you can.

2. **RESEARCH with evidence** — disambiguate from ground truth, not belief. Read the source-of-truth file;
   check live state (`gh`, `curl`, `git ls-remote`); test the assumption in a sandbox/clone; or compare
   against a proven reference repo. **One verified fact beats three plausible guesses.**

3. **RECORD an ADR** — append a short entry to [`DECISIONS.md`](./DECISIONS.md) in the
   **claim → evidence → decision → reversible?** format. **If you cannot cite evidence, you are NOT
   resolved → escalate to the operator; do not act.** "I'm fairly sure" is not evidence.

4. **ACT** — only now mutate. The PR/commit body **references the ADR** (`Refs DECISIONS.md ADR-xxx`) so
   the next agent inherits the resolution instead of re-deriving it.

The order is load-bearing. Skipping DETECT means you research the wrong question; skipping RESEARCH means
you record a guess; skipping RECORD means the next agent repeats your work (or your mistake).

## Enforcement (advisory, not blocking)

This gate is **guidance, kept visible at the moment of risk** — it is deliberately **not** a required
merge check (see `DECISIONS.md` ADR-006: on-prem gates were made additive + advisory so in-flight work is
never blocked; the same principle applies here). Three touchpoints, all advisory:

- **PR template** — `.github/pull_request_template.md` carries an `## Ambiguity Gate` checklist so the
  author affirms the gate ran (or that there was no ambiguity) at PR time.
- **CI parity step** — `semantic-pr.yml` runs [`check-pr-ambiguity.sh`](./check-pr-ambiguity.sh) against
  the PR body under `continue-on-error: true`. It surfaces a missing checklist or a hard-to-reverse box
  checked without a linked ADR — as a notice, never a block.
- **The script, runnable anywhere** — `check-pr-ambiguity.sh` reads a PR body (arg or stdin) and exits
  `0` when the checklist is present and any hard-to-reverse / boundary box has an `ADR-`/`DECISIONS.md`
  reference. Use it locally before opening a PR; mirrors the
  [`validate-conventional-title.sh`](../hooks/validate-conventional-title.sh) one-source-of-truth pattern.

## How it fits the system

The gate is not an isolated rule — it is one instance of the natural-systems design the whole multi-agent
estate is built on. See [`natural-systems.md`](./natural-systems.md) for the full physics / biology /
viral map; the gate specifically copies:

- **DNA proofreading + mismatch repair** — verify against the template (ground truth) *before* committing
  the base. RESEARCH-then-ACT is read-before-edit at the protocol level.
- **Locality / no action-at-a-distance** — effects propagate through local interactions, not jumps. Edit
  the *source*, let sync propagate; never reach across the public/private boundary (trigger #4; ADR-002,
  ADR-004).
- **Quorum sensing** — don't commit to a costly action until enough independent signals agree. An ADR
  requires ≥1 cited, verified fact before ACT.
- **Non-perturbing measurement** — observe without changing state: read-only probes, `--dry-run`,
  clone-and-inspect before you mutate.

It is the **error-correction** half of the coordination protocol; its sibling
[`agent-lease/`](../agent-lease/) is the **stigmergy** half. The lease stops two agents from *colliding*
on the same work (a shared mark in the environment); the gate stops a single agent from acting on a wrong
*assumption*. Together — coordinate through shared state, never act on unverified ambiguity — they are how
many agents with no central controller stay safe. A typical mutating task does both: `claim` the lease,
run the gate (recording an ADR if ambiguous), act, reference the ADR in the PR, `release` the lease.

## Relation to other frameworks

- [`agent-lease/`](../agent-lease/) — the collision-avoidance lease; the gate is its error-correction
  counterpart.
- [`natural-systems.md`](./natural-systems.md) — the *why*: the mechanisms nature uses for uncertainty +
  coordination that this gate copies.
- [`repo-governance/`](../repo-governance/) — the governance matrix lists this gate as an advisory PR
  control.
- [`deprecation-policy/`](../deprecation-policy/) — a deprecation is itself a hard-to-reverse action
  (trigger #6); record the decision in `DECISIONS.md` and ship the off-ramp.
