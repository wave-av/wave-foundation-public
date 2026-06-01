# Improvement Loop

The foundation's gates **find things**. The improvement loop **auto-feeds those findings forward** so the system gets stricter and cleaner over time without manual baby-sitting.

Every gate emits structured findings. Every finding gets a routing decision (auto-fix, auto-issue, auto-task, manual review). The autonomous `/loop` consumes the queue and works through it.

## The four feed-forward channels

### 1. Ratchet baseline auto-shrink

`shell ratchet` + `python ratchet` carry committed baselines of pre-existing lint debt. The loop:

- Re-runs the ratchet on master nightly
- If the live finding set is a **strict subset** of the baseline (i.e. real findings disappeared), auto-opens a PR shrinking the baseline
- Never auto-grows the baseline (that would mask new debt)
- Auto-PRs are labeled `ratchet-shrink` + `automerge` and require the 9 required checks

This is safe-by-construction: the only valid auto-update is "we got cleaner."

### 2. Dogfood-failure → tracked task

When `scripts/dogfood.sh` exits non-zero in CI (`dogfood-gate.yml`):

- The failing gate name + last-known-good SHA + the diff line range are extracted
- A row is appended to `docs/improvement-queue.md` (or an issue is opened if `IMPROVEMENT_QUEUE_AS_ISSUES=1`)
- The autonomous loop dequeues rows top-down and addresses them

Closed loop: when the gate goes green again, the loop deletes the row.

### 3. Bot review suggestions auto-applied (when structured)

The `pr-review-extract.sh` + `bot-review-gate.yml` pair already extracts structured findings. Phase-2 (this framework) adds:

- Suggestions emitted as **GitHub-native suggestion blocks** (CodeRabbit, Greptile) get auto-applied to a follow-up commit on the PR — but only when:
  - the PR has the `auto-suggest` label, AND
  - the suggestion is single-file, single-hunk, AND
  - the suggested replacement parses (TS/Python/Shell — language-aware), AND
  - the suggested replacement does not touch `.github/`, `scripts/`, `plugin/`, or any security-relevant root file
- Multi-hunk or cross-file suggestions are summarized into a `### Suggested follow-ups` block of the sticky comment instead

The boundary is conservative on purpose: silent edits to gate-critical code is exactly the failure mode we want to prevent.

### 4. PR-review context → follow-up tasks

`pr-review-extract.sh` already emits a JSON artifact (`pr-review-context.json`). The loop:

- On merge, reads the merged-PR's artifact
- Files unresolved findings into `docs/follow-up-tasks.md` keyed by `(file, line, finding-class)`
- De-dupes against existing rows
- The autonomous loop picks them up like any other task

## The validator wiring

Each feed-forward channel has a **validator** before it commits anything:

| Channel | Validator | Failure handling |
|---------|-----------|------------------|
| Baseline shrink | live findings ⊂ baseline AND all 9 required checks pass on the auto-PR | abort + alert |
| Dogfood task | the failing gate is in the known-gate set | abort + alert (catches a renamed gate the loop hasn't learned) |
| Bot-suggestion apply | suggestion parses + scoped to allow-list dirs + diff size < 50 lines | leave as comment-only |
| PR follow-up | finding has structured severity tag (per Bot Review Gate rules) | drop on the floor (we already filter prose) |

The validators run inside the autonomous loop. The loop never short-circuits a validator on "this looks fine".

## Autonomous loop integration

`/loop` (the autonomous variant) reads `docs/improvement-queue.md` + `docs/follow-up-tasks.md` as its work list. Per cycle:

1. Pull next pending item
2. Identify the gate / finding it represents
3. Reproduce locally (re-run the gate, confirm finding still exists)
4. If reproducible → fix → run dogfood → commit → PR → shepherd to merge
5. If NOT reproducible → mark item resolved (with timestamp + reason)

Cycle cadence: between 1200s and 1800s (idle ticks) — long enough that prompt-cache misses are amortized over real work, short enough that fresh findings get actioned same-day.

## Anti-patterns

- ❌ Auto-applying any change to `.github/workflows/` or `scripts/` (validators block this — never override)
- ❌ Closing a follow-up task without verifying the underlying finding is actually fixed
- ❌ Running the loop against a branch (it operates on master + opens its own branches)
- ❌ Letting the queue grow unbounded with no cycle running (alert when queue depth > 50 unresolved)

## State files

| File | Purpose |
|------|---------|
| `docs/improvement-queue.md` | dogfood failures awaiting action |
| `docs/follow-up-tasks.md` | bot-extracted unresolved findings |
| `.improvement-loop-state.json` (gitignored, per-machine) | last-cycle timestamps + cooldowns |

## Cross-references

- [`scripts/dogfood.sh`](../../scripts/dogfood.sh) — the gate source
- [`scripts/pr-review-extract.sh`](../../scripts/pr-review-extract.sh) — finding source
- [`.github/workflows/ratchet.yml`](../../.github/workflows/ratchet.yml) — baseline source
- [`docs/ratchet.md`](../../docs/ratchet.md) — ratchet semantics this loop respects
