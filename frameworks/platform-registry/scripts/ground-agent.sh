#!/usr/bin/env bash
# Agent grounding — emit a one-page summary of the current platform from state.json.
#
# Read state.json from an EXPLICIT source — a local path or a URL you supply — and
# produce a short markdown briefing for Claude / agent sessions to read on start.
# The output is designed to be injected into the session context (e.g. via
# Claude Code's `SessionStart` hook or an `AGENTS.md` include).
#
# There is deliberately NO built-in default source. The registry's state.json is
# generated inside a repo that a public consumer cannot read, so a baked-in URL
# would 404 in every consumer environment while looking perfectly fine in CI. The
# script now refuses to guess and tells you what to pass instead. Choosing a
# publicly-resolvable source for state.json is tracked in #102.
#
# Usage:
#   bash ground-agent.sh --state path/to/state.json   # read a local snapshot
#   WAVE_PLATFORM_STATE_URL=<url> bash ground-agent.sh  # fetch a published snapshot
#   bash ground-agent.sh --json                       # emit raw JSON instead of markdown
#
# Output goes to stdout; redirect to wherever your session-start hook reads from.

set -euo pipefail

# Optional published-snapshot URL. Empty unless the caller sets it — see header.
STATE_URL="${WAVE_PLATFORM_STATE_URL:-}"
JSON_OUT=false
STATE_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --state) STATE_PATH=$2; shift 2 ;;
    --json) JSON_OUT=true; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$STATE_PATH" ]; then
  SOURCE_DESC="$STATE_PATH"
  raw=$(cat "$STATE_PATH")
elif [ -n "$STATE_URL" ]; then
  SOURCE_DESC="$STATE_URL"
  # curl's stderr is NOT redirected to /dev/null: a failed grounding fetch must be
  # readable, not swallowed. `|| { ... }` rather than `|| true` so a non-2xx/network
  # failure ends the run instead of silently producing an empty briefing.
  if ! raw=$(curl -sSfL "$STATE_URL"); then
    echo "ground-agent: could not fetch state.json from \$WAVE_PLATFORM_STATE_URL ($STATE_URL)" >&2
    echo "  fix: check the URL is reachable from here, or pass --state <path/to/state.json> to read a local snapshot" >&2
    exit 1
  fi
  if [ -z "$raw" ]; then
    echo "ground-agent: \$WAVE_PLATFORM_STATE_URL ($STATE_URL) returned an empty body — refusing to ground an agent on nothing" >&2
    echo "  fix: verify the URL serves the raw state.json, or pass --state <path/to/state.json>" >&2
    exit 1
  fi
else
  # Fail LOUD and explicit. The previous behaviour here was a hardcoded fetch from a
  # repo a public consumer cannot read: green in CI, 404 at run time, and the error
  # was routed to /dev/null. Refusing to guess is the correct failure contract for a
  # grounding script — a wrong or empty briefing is worse than no briefing.
  echo "ground-agent: no state.json source configured — refusing to guess." >&2
  echo "  fix: pass --state <path/to/state.json> to read a local snapshot," >&2
  echo "       or set WAVE_PLATFORM_STATE_URL=<url> to fetch a published one." >&2
  exit 2
fi

if [ "$JSON_OUT" = "true" ]; then
  echo "$raw"
  exit 0
fi

# Emit markdown: header, per-layer table, key claims (Rule 1).
python3 - <<PY
import json, sys
state = json.loads("""$raw""")
caps = state.get("capabilities", [])
gen_at = state.get("generatedAt", "unknown")
total = len(caps)

print(f"# WAVE platform state (loaded for agent grounding)")
print()
print(f"_Source:_ \`$SOURCE_DESC\` (content last changed {gen_at})")
print(f"_Repos:_ {total}")
print()
print("## Grounding rules (Rule 1: read this before claiming any WAVE capability exists)")
print()
print("- A WAVE repo, product, endpoint, or MCP tool is **real** only if it appears here.")
print("- If you reference something not in this list, the registry validator will reject your PR.")
print("- When adding a new capability, update the consumer repo's \`capabilities.json\` in the **same PR** that introduces the capability.")
print()
print("## Layer 0 — Operator")
layer0 = [c for c in caps if c.get("planeLayer") == 0]
if layer0:
  for c in layer0:
    print(f"- \`{c['repo']}\` ({c.get('version','?')}, {c.get('lifecycle','?')}) — {' · '.join(c.get('tags', []) or ['—'])[:80]}")
else:
  print("_(no Layer 0 repos in registry yet)_")
print()
print("## Layer 1 — Edge")
layer1 = [c for c in caps if c.get("planeLayer") == 1]
if layer1:
  for c in layer1:
    print(f"- \`{c['repo']}\` ({c.get('version','?')}, {c.get('lifecycle','?')})")
else:
  print("_(no Layer 1 repos in registry yet)_")
print()
print("## Layer 2 — Bridges")
layer2 = [c for c in caps if c.get("planeLayer") == 2]
if layer2:
  for c in layer2:
    print(f"- \`{c['repo']}\` ({c.get('version','?')}, {c.get('lifecycle','?')})")
else:
  print("_(no Layer 2 repos in registry yet)_")
print()
print("## Layer 3 — Local")
layer3 = [c for c in caps if c.get("planeLayer") == 3]
if layer3:
  for c in layer3:
    print(f"- \`{c['repo']}\` ({c.get('version','?')}, {c.get('lifecycle','?')})")
else:
  print("_(no Layer 3 repos in registry yet)_")
print()
print("## Layer 4 — Hardware")
layer4 = [c for c in caps if c.get("planeLayer") == 4]
if layer4:
  for c in layer4:
    print(f"- \`{c['repo']}\` ({c.get('version','?')}, {c.get('lifecycle','?')})")
else:
  print("_(no Layer 4 repos in registry yet)_")
print()
non_plane = [c for c in caps if c.get("planeLayer") is None]
if non_plane:
  print("## Non-plane (SDKs, marketing, agent tooling, governance)")
  for c in non_plane:
    print(f"- \`{c['repo']}\` ({c.get('version','?')}, {c.get('lifecycle','?')})")
  print()

# Sunsetting / archived warnings
sunsetting = [c for c in caps if c.get("lifecycle") in ("sunsetting", "archived")]
if sunsetting:
  print("## ⚠️ Sunsetting / archived — do not build new dependencies on these")
  for c in sunsetting:
    print(f"- \`{c['repo']}\` ({c.get('lifecycle','?')})")
  print()
PY
