#!/usr/bin/env bash
# PreToolUse(Bash) — Doppler env-key guard (ENFORCEMENT, not advice).
# If a Bash command references a secret-shaped env var that is UNSET in this shell and the command
# isn't already going through Doppler, then:
#   • if Doppler is KNOWN to hold that secret (from doppler-secrets-cache.sh) → DENY with the exact
#     `doppler run` to use. This is the forcing function that makes me actually go to Doppler.
#   • otherwise → a non-blocking nudge to check Doppler before concluding a key is "missing".
# Recoverable by design: the corrected `doppler run ...` retry matches the doppler-bypass below.
set -u
input="$(cat)"
cmd="$(printf '%s' "$input" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Already using Doppler (run/secrets/etc) → allow silently. Also lets the corrected retry through.
printf '%s' "$cmd" | grep -q 'doppler' && exit 0

CACHE="/tmp/claude/doppler-secrets.cache"
# referenced shell vars: $FOO or ${FOO}
# shellcheck disable=SC2016  # the $ is part of the grep regex, not a shell expansion
vars="$(printf '%s' "$cmd" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' | tr -d '${}' | sort -u)"
[ -n "$vars" ] || exit 0

emit_deny() { # $1 = reason text
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')"
}
emit_ctx() { # $1 = context text
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import sys,json;print(json.dumps(sys.stdin.read()))')"
}

blocked=""; nudge=""
for v in $vars; do
  case "$v" in
    *API_KEY|*_TOKEN|*_SECRET|*_PASSWORD|*PRIVATE_KEY|*SERVICE_ROLE*|*ACCESS_KEY|*_DSN|\
    ANTHROPIC_*|OPENAI_*|SUPABASE_*|STRIPE_*|CLOUDFLARE_*|PRIVY_*) ;;
    *) continue ;;
  esac
  loc=""
  [ -f "$CACHE" ] && loc="$(awk -F'\t' -v n="$v" '$1==n{print $2; exit}' "$CACHE")"
  if [ -n "$loc" ]; then
    # Known in Doppler → ENFORCE Doppler regardless of any shell value. A shell value here is
    # untrustworthy (the original incident was a STALE env key shadowing the real Doppler one).
    blocked="${blocked}
  • \$$v  →  doppler run --project ${loc%/*} --config ${loc#*/} --command '<your command>'"
  else
    # Unknown to Doppler → only nudge if it's actually unset ($v is [A-Za-z0-9_], indirect-expand safe).
    cur=${!v:-}
    [ -n "${cur:-}" ] && continue
    nudge="$nudge \$$v"
  fi
done

if [ -n "$blocked" ]; then
  emit_deny "✋ This command relies on a secret that is UNSET in the shell but EXISTS in Doppler (the canonical secret store). Do NOT conclude it's missing/rejected and do NOT hardcode it — re-run THROUGH Doppler:${blocked}

Wrap the whole command in 'doppler run'. (This guard fires because doppler-secrets-cache.sh confirmed the key is in Doppler.)"
  exit 0
fi
if [ -n "$nudge" ]; then
  emit_ctx "ℹ️ Secret-shaped var(s) unset here:${nudge}. Before assuming a key is missing, check Doppler first — doppler secrets --only-names --project <p> --config <c> — then wrap the command in 'doppler run'. Never judge a secret's availability from the shell env alone."
  exit 0
fi
exit 0
