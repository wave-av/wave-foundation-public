# `frameworks/media-engine-smoke-gate/` — created-and-proven, or it isn't done

The convention that built the WAVE Media Engine: **nothing in the media stack is "done"
until it is (1) actually created as code and (2) proven by a deterministic end-to-end smoke
that runs in CI on every push.** No design doc, no "scaffold", no "wired up" counts as
complete. If you can't point at a green smoke that exercises the thing, it doesn't exist.

This is the discipline that produced the engine's 14 E2E smokes (R1 clock … R9 fabric +
every cross-cutting concern) — each module landed with its own `WAVE <X> TEST PASS` smoke
wired into `build.sh` + CMake `ctest` + the CI workflow, in the same PR.

## The rule

A media-engine module/adapter PR is complete only when ALL hold:

1. **Created** — real code exists (a header/impl/module), not a placeholder or a no-op.
2. **Smoked** — a dependency-free E2E test exercises it and prints a unique sentinel line
   `WAVE <THING> TEST PASS` on success, exiting non-zero on any failure.
3. **Wired** — the smoke is invoked by the repo's build (`build.sh` / `ctest` / `npm test`)
   AND asserted in CI: `./engine/wave-x-test | grep -q "WAVE X TEST PASS"`.
4. **Green** — that CI step passes on the PR. A red or absent smoke = not done.

The sentinel-grep matters: a test that exits 0 but silently skipped everything still fails
the gate, because the grep for the explicit PASS line won't match. "Tests pass" is not the
claim — "this specific behavior was exercised and matched the sentinel" is.

## Why

The engine is the spine every transport/bridge/edge consumes. A regression in R2 integrity
or R1 timing is invisible until a customer's stream drifts or desyncs. Deterministic smokes
(no hardware, no network, fixed oracle values) catch it at PR time, on every push, for free.
The cost of one smoke is ~50 lines; the cost of a silent core regression is a broadcast.

## Contents

| File | Purpose |
|---|---|
| `README.md` | This file — the convention. |
| `audit-prompts.md` | Prompts an agent/reviewer runs before claiming a media module done. |
| `check-smoke-gate.sh` | Advisory CI helper: for a CI workflow + build file, verifies every `*-test` built is also asserted with a `grep -q "… TEST PASS"` sentinel. Flags built-but-unasserted smokes. |

## Wiring

`check-smoke-gate.sh` is advisory (exit 0 with warnings) — it reports built-but-unasserted
smokes so the gate can't rot silently. A media repo opts in by calling it in CI after its
build step. It is intentionally NON-blocking: the blocking guarantee is the per-smoke
`grep -q` in the repo's own CI (layer 3 above); this script is the meta-check that the
greps exist at all.

## Relationship to other frameworks

- [`never-done`](../never-done/) — closure is an invitation to file follow-ups. Smoke-gate is
  the inverse pre-condition: don't even *claim* closure until created+proven.
- The engine's `GUARDRAIL.md` (maintained in the internal media-engine repo)
  keeps the engine core-only; this gate keeps it *proven*.
