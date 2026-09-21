# `frameworks/never-done/` — the audit-on-closure framework

Operationalizes [`rules/never-done.md`](../../rules/never-done.md): every
closure event is an invitation to file follow-ups, not an exit.

## Contents

| File | Purpose |
|---|---|
| `README.md` | This file. |
| `audit-prompts.md` | The standard prompt set posted on every closing PR. Markdown-checklist style; author copies to a follow-up issue when something needs tracking. |
| `generate-comment.sh` | The CI helper. Reads the PR body for closure patterns (`closes #N`, `fixes #N`, Linear `WAVE-NNNNN`), emits the audit-prompts comment markdown to stdout. |
| `post-comment.sh` | Wraps `generate-comment.sh` + `gh pr comment`. Idempotent: skips if the audit prompts comment already exists. |
| `example-spoke-workflow.yml` | Template a consuming repo copies to `.github/workflows/never-done.yml`. Calls a hub reusable workflow that is NOT shipped in this public repository — you must supply your own (see the note in the file). |

## Wiring

Two layers:

**Scripts (auto-vendored):** consumers running
[`scripts/consume.sh`](../../scripts/consume.sh) get
`.foundation/frameworks/never-done/{generate,post}-comment.sh` (the
`frameworks/` directory is part of the canonical vendor set — see
`VENDOR_DIRS` in `consume.sh`). No per-spoke action needed.

**Workflow (opt-in):** a *reusable* workflow (`on: workflow_call`,
conventionally `.github/workflows/never-done.yml`) implements the
audit-prompt-posting logic. **This public repository does not ship that hub
workflow** — only the spoke template below and the vendored scripts above.
Spokes opt in by adding [`example-spoke-workflow.yml`](./example-spoke-workflow.yml)
to their own `.github/workflows/never-done.yml`. That file:

1. Triggers on PR `opened` / `edited` / `synchronize` / `reopened`.
2. Grants `pull-requests: write` (REQUIRED — a reusable workflow cannot
   elevate permissions the caller didn't grant; the comment poster fails
   silently without it).
3. Calls a hub workflow implementing this contract — you must publish your
   own (see the note in `example-spoke-workflow.yml`); a `uses:` pointing at
   a repo you don't control and can't reach will never resolve.

Once both layers are in place, every PR closure-pattern triggers the
audit comment. No-op if the framework isn't vendored (graceful
degradation, per `continue-on-error: true`).

What happens on a PR:

1. The workflow calls `post-comment.sh`, which:
   - Parses the PR body for closure patterns.
   - If any found AND no prior audit-prompts comment exists → posts one.
   - If none found → silent (PR doesn't claim to close anything).
2. The comment is the invitation. Author acknowledges either by filing
   follow-up issues OR by replying "no follow-ups identified after audit."

## Why this is non-blocking

The gate is **advisory** (`continue-on-error: true`). Per founder framing
2026-06-01: blocking adds ritual friction; real work routes around it.
The invitation surfaces the audit moment without halting the team.

## Detection patterns

The script recognises the following closure markers in PR body:

- `closes #N`, `fixes #N`, `resolves #N` (GitHub)
- `WAVE-N`, `[WAVE-N]` (Linear)
- `Closes: WAVE-N` (Linear long form)

Case-insensitive. Markers in code blocks or quoted strings are skipped.

## When to manually invoke

- After a release tag is cut: run `generate-comment.sh` against the
  release notes to surface follow-up candidates.
- After incident resolution: run it against the post-mortem doc to
  catch hidden follow-ups.
- Quarterly: as part of the rolling-readiness audit
  ([WAVE-25150](https://linear.app/wave-inc/issue/WAVE-25150)).

## See also

- [`rules/never-done.md`](../../rules/never-done.md) — the canonical rule this operationalizes.
- [`frameworks/methodologies/done-is-a-trigger.md`](../methodologies/done-is-a-trigger.md) —
  methodology #25: the catalog view + the agent's five-lens DONE→AUDIT checklist.
