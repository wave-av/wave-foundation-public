#!/usr/bin/env bash
# check-model-thinking-capability.sh — keep a claude-code-router (ccr) config consistent
# with the live model thinking-capability map, so a non-reasoning model is never wired to
# receive the Anthropic `thinking` param (Ollama 400s "<model> does not support thinking").
#
# A shared gate (peer of check-model-strings.sh): vendored into spokes via consume.sh and run
# from pre-commit + CI off this one script. Repos that don't use ccr have neither input file and
# pass trivially (n/a) — the check only engages where a ccr config + capability map both exist.
#
# Inputs (args override env override conventional defaults):
#   --map  PATH   model thinking-capability map   (env MODEL_CAP_MAP;  default docs/model-thinking-capability.json)
#   --config PATH ccr config.json                 (env CCR_CONFIG;     default config/ccr/config.json)
#   --fanout PATH fan-out script (merge-model hint)(env FANOUT;        default scripts/fan-out-inference.sh)
#   --ci          accepted for parity (warnings stay non-fatal; only a real misconfig exits 1)
#
# Rule: rules/local-llm-thinking-capability.md
# Exit: 0 = pass (warnings allowed) or n/a; 1 = FAIL (non-reasoning model missing strip-thinking)
set -euo pipefail

MAP="${MODEL_CAP_MAP:-docs/model-thinking-capability.json}"
CONFIG="${CCR_CONFIG:-config/ccr/config.json}"
FANOUT="${FANOUT:-scripts/fan-out-inference.sh}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --map) MAP="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --fanout) FANOUT="$2"; shift 2 ;;
    --ci) shift ;;
    *) echo "model-thinking: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# Engage only where a ccr config exists — repos without one are not in scope.
if [ ! -f "$CONFIG" ]; then
  echo "model-thinking: ✓ n/a (no ccr config at $CONFIG)"
  exit 0
fi
if [ ! -f "$MAP" ]; then
  echo "model-thinking: ⚠ ccr config present but capability map missing ($MAP) —" \
    "run gen-model-thinking-capability.sh; cannot verify thinking routing" >&2
  exit 0
fi

# Default fan-out merge model, parsed from the script's FAN_MERGE_MODEL default (best-effort).
MERGE_DEFAULT=""
if [ -f "$FANOUT" ]; then
  # shellcheck disable=SC2016  # literal regex matching the source text ${FAN_MODEL:-...}; must NOT expand
  MERGE_DEFAULT="$(sed -n 's/.*FAN_MERGE_MODEL:-\${FAN_MODEL:-\([^}]*\)}.*/\1/p' "$FANOUT" | head -1)"
fi

python3 - "$MAP" "$CONFIG" "${MERGE_DEFAULT:-}" <<'PY'
import datetime
import json
import sys

map_path, ccr_path, merge_default = sys.argv[1], sys.argv[2], sys.argv[3]
fails, warns = [], []

cap = json.load(open(map_path))


def _no_latest(n):  # py3.8-safe: str.removesuffix is 3.9+, and this gate is vendored to spokes
    return n[: -len(":latest")] if n.endswith(":latest") else n


thinking = {}
for m in (cap.get("models") or []):
    name = m["name"]
    thinking[name] = m["thinking"]
    thinking[_no_latest(name)] = m["thinking"]


def is_thinking(name):
    if name in thinking:
        return thinking[name]
    if _no_latest(name) in thinking:
        return thinking[_no_latest(name)]
    return None


# Staleness (advisory) — date arithmetic only, no wall-clock dependency beyond today.
gen = cap.get("generated_at", "")
try:
    age = (datetime.date.today() - datetime.date.fromisoformat(gen[:10])).days
    if age > 30:
        warns.append(f"capability map is {age}d old (>30d) — regenerate gen-model-thinking-capability.sh")
except Exception:
    warns.append(f"capability map generated_at unparseable: {gen!r}")

ccr = json.load(open(ccr_path))
# A ccr config has one or more Providers; each provider's transformer map carries a
# reserved `use` array (the provider-level default applied to models with no override)
# plus optional per-model entries. In ccr, a per-model `use` REPLACES the provider
# default for that model (it does not merge) — so a model's effective transformer list
# is its own `use` when present, else the provider default.
providers = ccr.get("Providers") or []
if not providers:
    warns.append("ccr config has no Providers[] — nothing to validate")
for provider in providers:
    tf = provider.get("transformer", {})
    if not isinstance(tf, dict):
        continue
    provider_use = tf.get("use") if isinstance(tf.get("use"), list) else []
    # Models listed on the provider (covered by the default) + any with per-model overrides.
    models = set(provider.get("models") or [])
    models.update(k for k in tf if k != "use")
    for model in sorted(models):
        spec = tf.get(model)
        if isinstance(spec, dict) and isinstance(spec.get("use"), list):
            use = spec["use"]          # per-model use REPLACES the provider default
        else:
            use = provider_use         # model relies on the provider-level default
        # The rule requires strip-thinking FIRST — it must run before `openai`, which
        # would otherwise see (and may mistranslate) the thinking field. Check position,
        # not just presence.
        strip_idx = next(
            (i for i, u in enumerate(use) if isinstance(u, str) and u == "strip-thinking"), -1
        )
        t = is_thinking(model)
        if t is None:
            warns.append(f"ccr model '{model}' not in capability map — regenerate map")
        elif t is False and strip_idx < 0:
            fails.append(f"ccr model '{model}' is non-reasoning but MISSING strip-thinking (will 400)")
        elif t is False and strip_idx > 0:
            fails.append(f"ccr model '{model}' is non-reasoning: strip-thinking must be FIRST in use "
                         f"(must run before 'openai'); found at index {strip_idx}")
        elif t is True and strip_idx >= 0:
            warns.append(f"ccr model '{model}' is reasoning but has strip-thinking (stripped unnecessarily)")

if merge_default:
    t = is_thinking(merge_default)
    if t is False:
        warns.append(f"fan-out default merge model '{merge_default}' is NOT a reasoning model (synthesis quality)")
    elif t is None:
        warns.append(f"fan-out default merge model '{merge_default}' not in capability map")

for w in warns:
    print(f"model-thinking: ⚠ {w}", file=sys.stderr)
for f in fails:
    print(f"model-thinking: ✗ {f}", file=sys.stderr)

if fails:
    print(f"model-thinking: {len(fails)} failure(s), {len(warns)} warning(s) — FAIL", file=sys.stderr)
    sys.exit(1)
print(f"model-thinking: ✓ thinking-capability routing consistent ({len(warns)} warning(s))")
PY
