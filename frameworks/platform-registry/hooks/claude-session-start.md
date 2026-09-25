# Claude Code session-start hook — agent grounding (Phase F)

> Drop this hook into any wave-av repo to have every Claude session read the platform-registry state at session start.

## Install

The hook runs `ground-agent.sh` **from a checkout you already have**, against a `state.json` you name explicitly. Point `WAVE_PLATFORM_REGISTRY` at your local `frameworks/platform-registry` directory, then add to your project's `.claude/settings.json` (or `$HOME/.claude/settings.json` for global):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash \"$WAVE_PLATFORM_REGISTRY/scripts/ground-agent.sh\" --state \"$WAVE_PLATFORM_REGISTRY/state.json\""
      }
    ]
  }
}
```

To ground against a published snapshot instead of a file on disk, drop `--state` and set `WAVE_PLATFORM_STATE_URL` to the URL that serves the raw `state.json` in your environment:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash \"$WAVE_PLATFORM_REGISTRY/scripts/ground-agent.sh\""
      }
    ]
  }
}
```

The hook prints a markdown briefing to stdout; Claude Code injects stdout into the session context automatically.

### Why not `curl … | bash`

This page used to document a one-liner that piped a remotely-fetched copy of `ground-agent.sh` straight into `bash`, with `2>/dev/null` on the end. Two things were wrong with it, and both are worth stating because the shape is tempting:

1. **It executed an unreviewed remote script on every session start.** Whatever that URL served at that moment ran with the developer's privileges, before the first user turn, with no pinning and no review step.
2. **It failed silently.** The URL pointed into a repo most consumers cannot read, so the fetch 404'd — and `2>/dev/null` discarded the error. The session then started with *no* grounding while looking exactly like a session that had been grounded, which is the precise failure this hook exists to prevent. A missing briefing you can see beats a missing briefing you cannot.

`ground-agent.sh` now refuses to guess a source: with neither `--state` nor `WAVE_PLATFORM_STATE_URL` it exits non-zero and prints what to pass. Which URL should be the canonical published source is an open decision, tracked in [#102](https://github.com/wave-av/wave-foundation-public/issues/102).

## What the briefing contains

- Total repo count + when state.json was last refreshed
- The 4 grounding rules (Rule 1: capability not in registry = not real)
- Per-layer table of every WAVE repo with version + lifecycle
- Sunsetting / archived warnings (prevents new dependencies on legacy)

## How this closes Rule 4

[`AGENT-GROUNDING.md`](../AGENT-GROUNDING.md) Rule 4 says agents should read `state.json` on session start. This hook is the literal implementation. Before this, agents had to *remember* to do it. With the hook, it happens unprompted before the first user turn.

## What it doesn't replace

- Per-repo `CLAUDE.md` / `AGENTS.md`: still describes how to work in that repo.
- The CI validator from Phase E: still catches drift at PR open.

The session-start grounding is **prevention** (don't make stuff up); the CI validator is **detection** (catch it before merge).
