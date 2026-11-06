# Claude Code session-start hook — agent grounding (Phase F)

> Drop this hook into any wave-av repo to have every Claude session read the platform-registry state at session start.

## Quick install

Add to your project's `.claude/settings.json` (or copy to `$HOME/.claude/settings.json` for global):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash -c 'curl -sSfL https://raw.githubusercontent.com/wave-av/wave-foundation/v1/frameworks/platform-registry/scripts/ground-agent.sh | bash 2>/dev/null'"
      }
    ]
  }
}
```

The hook prints a markdown briefing to stdout; Claude Code injects stdout into the session context automatically.

## What the briefing contains

- Total repo count + when state.json was last refreshed
- The 4 grounding rules (Rule 1: capability not in registry = not real)
- Per-layer table of every WAVE repo with version + lifecycle
- Sunsetting / archived warnings (prevents new dependencies on legacy)

## Local development variant

If you're working on `wave-foundation` itself, point at the local file rather than fetching:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash $HOME/path/to/wave-foundation/frameworks/platform-registry/scripts/ground-agent.sh --state $HOME/path/to/wave-foundation/frameworks/platform-registry/state.json"
      }
    ]
  }
}
```

## How this closes Rule 4

[`AGENT-GROUNDING.md`](../AGENT-GROUNDING.md) Rule 4 says agents should read `state.json` on session start. This hook is the literal implementation. Before this, agents had to *remember* to do it. With the hook, it happens unprompted before the first user turn.

## What it doesn't replace

- Per-repo `CLAUDE.md` / `AGENTS.md`: still describes how to work in that repo.
- The CI validator from Phase E: still catches drift at PR open.

The session-start grounding is **prevention** (don't make stuff up); the CI validator is **detection** (catch it before merge).
