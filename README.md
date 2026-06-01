# wave-foundation (public mirror)

The open, public mirror of WAVE's build-standards foundation — the versioned source of
truth for **how WAVE builds** across its projects: cross-project rules, functional
frameworks, design tokens, taxonomies, JSON schemas, and the installable Claude Code
plugin (guard hooks + skills).

> This repository is a **read-only mirror**. It is synced by pull request from a private
> source repository and carries only the allowlisted, business-ref-free subset. The sync
> is automated and the mirror is continuously verified to match its source exactly.

## What's inside

| Path | What |
|------|------|
| `plugin/` | The installable Claude Code plugin — guard hooks + skills |
| `rules/` | Cross-project MUST/NEVER build conventions |
| `frameworks/` | Functional capabilities, each a self-contained framework with its own README (identity-money, claude-api, observability, harvest, gates, copywriting, and more) |
| `design-system/` | OKLCH color tokens + per-product accent rules |
| `taxonomy/` | Shared labels, skills, products, audiences |
| `schemas/` | JSON Schemas |
| `docs/` | Selected runbooks + diagrams |

## Consuming it

Two independent layers — pick what you need:

- **Plugin** (hooks + skills, runs at agent-session time):
  `claude /plugin install wave-av/wave-foundation-public`
- **Vendor / submodule** (rules + frameworks + design tokens + taxonomies as a read-only
  `.foundation/` tree): use `scripts/consume.sh` from the consuming repo, or add this repo
  as a submodule and pin it.

## License

[Apache License 2.0](LICENSE) — permissive, with an explicit patent grant. Copyright WAVE Online LLC.

## Contributing

Because this is an automated mirror, fixes generally land in the upstream source and flow
here on the next sync. Issues and discussion are welcome; direct PRs to mirrored paths will
be overwritten by the next sync.
