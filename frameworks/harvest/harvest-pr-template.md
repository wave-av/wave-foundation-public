# Harvest PR — description template

Copy/paste into the PR body when running a harvest. The harvest script
(`scripts/harvest-from-repo.sh`) auto-fills the bracketed fields where possible.

```markdown
## Harvest summary

- **Source**: [`wave-av/<source-repo>/<path>`](https://github.com/wave-av/<source-repo>/blob/<sha>/<path>)
- **Source SHA**: `<40-char>`
- **Harvested by**: `@<agent-or-user>`
- **Promotion target**: `frameworks/<which>` (or `rules/`, `taxonomy/`, `design-system/`)

## Why this is a foundation candidate

<1-2 sentences: what does this pattern give us that's not yet in the foundation?>

## Proven in (≥2 spokes — non-negotiable)

| Repo | Path | Notes |
|------|------|-------|
| `wave-av/<repo-1>` | `<path>` | <1-line context> |
| `wave-av/<repo-2>` | `<path>` | <1-line context> |

## What this PR changes

Only `staging/<source-repo>/<path>` — a faithful copy of the source file with
provenance frontmatter. No canonical files in this PR. Promotion ships as a
separate follow-up.

## Promotion plan

When promoting (see `docs/promotion.md`), the next PR will:

1. Move/copy the file into `<promotion_target>/`.
2. Strip business specifics.
3. Generalize tool-specific refs.
4. Add a README pointer in the parent dir's index.
5. Pass markdownlint + codespell + skill-validate + file-size + claude-api-shape.

## Open questions

- <If unsure which canonical dir, ask here>
- <If unsure about a specific abstraction, ask here>

## Checklist

- [ ] Source file copied byte-for-byte
- [ ] Provenance frontmatter prepended
- [ ] Source SHA pinned (not a moving branch ref)
- [ ] ≥2 proven-in references cited
- [ ] `harvest` label applied
- [ ] `staging/` is the ONLY touched root dir
```

## Style notes

- Keep the description terse. The provenance frontmatter inside the file is the
  source of truth; the PR description is the human-readable summary.
- "Promotion plan" is non-binding — the harvester's hypothesis. The actual
  promotion PR can revise.
- Surface tradeoffs in "Open questions" (which canonical dir, which abstraction
  shape) — reviewers respond there, not inline.
