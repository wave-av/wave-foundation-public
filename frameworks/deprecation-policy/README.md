# Deprecation Policy — how WAVE sunsets things

Everything the foundation ships is **consumed, not copied** — so removing a rule,
framework, skill, migration, script, or API endpoint breaks consumers unless it is
sunset deliberately. This is the one process for retiring anything, so a consumer
is never surprised by a thing that vanished.

## The three phases

| Phase | What | Min duration |
|-------|------|--------------|
| **1. Announce** | mark deprecated + name the replacement + log it in `DEPRECATIONS.md`. Still works, unchanged. | one minor release |
| **2. Warn** | emit a runtime/CI warning on use; the thing still works. | one minor release |
| **3. Remove** | delete in the next **major**. The `DEPRECATIONS.md` entry moves to "Removed in vX". | major release only |

A breaking removal **only** happens at a major version. Consumers pin the moving
major tag (`@v1`) precisely so a minor never breaks them — see
[`consumer-attestation`](../consumer-attestation/). Skipping to "Remove" without
Announce+Warn is the thing this policy exists to prevent.

## The deprecation must ship its own off-ramp

An announcement without a replacement is a dead end. Every Phase-1 entry MUST name:

- **the replacement** (or "no replacement — here's why"), and
- **the migration path** — the concrete steps/command to move, not "see docs".

If you can't write the migration path, it isn't ready to deprecate.

## DEPRECATIONS.md ledger

A single tracked file at the repo root. One entry per deprecated thing:

```markdown
## `frameworks/foo` → `frameworks/bar`
- **Announced:** 1.7.0 (2026-05-31)
- **Warns since:** 1.8.0
- **Removes in:** 2.0.0
- **Why:** bar subsumes foo + adds X.
- **Migrate:** replace `import foo` with `import bar`; `bar` is API-compatible except `foo.q()` → `bar.query()`.
```

CI asserts: nothing referenced by a `Removes in: <current-major>` entry still
exists past that major; and no Phase-1 entry lacks a **Migrate:** line.

## Surfacing the warning

- **Rules/docs:** a `> **Deprecated (since X.Y):** use [bar] instead.` admonition at the top.
- **Scripts/CLIs:** print to stderr on invocation (never stdout — don't corrupt piped output).
- **Migrations/SQL:** `COMMENT ON … IS 'DEPRECATED vX.Y → use …'`; never silently drop.
- **Skills/plugin:** note in the skill description so the loader/agent sees it.

## Anti-patterns

- ❌ Removing in a minor (breaks `@v1` consumers — the whole point of the major tag).
- ❌ Announcing without a replacement or migration path (a dead end, not a deprecation).
- ❌ Deleting the `DEPRECATIONS.md` entry on removal — move it to "Removed in vX" so the history is auditable.
- ❌ A warning on stdout for a CLI (corrupts pipelines) — warnings go to stderr.
- ❌ Silent behavior change dressed up as "deprecation" — deprecation keeps behavior, just flags it.

## Relation to other frameworks

- [`consumer-attestation`](../consumer-attestation/) — the `@v1` major-tag pin this policy protects.
- [`tech-debt`](../tech-debt/) — deprecations are planned debt paydown; track carrying cost there.
- `RELEASING.md` — major-tag mechanics (a removal rides a major bump).
