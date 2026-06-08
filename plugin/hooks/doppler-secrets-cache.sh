#!/usr/bin/env bash
# SessionStart — cache the NAMES (never values) of secrets available in Doppler, so the env-key
# guard (doppler-env-guard.sh) can tell instantly + offline that a referenced secret IS in Doppler
# and exactly where. This is the "you KNOW to go to Doppler" half of the enforcement system:
# rules/memories are passive; this gives the guard ground truth to act on.
#
# Scopes default to the most-used project/config pairs; override with WAVE_DOPPLER_SCOPES
# (space-separated "project/config"). Best-effort: needs doppler installed + authed; never blocks.
set +e
command -v doppler >/dev/null 2>&1 || exit 0

OUT="/tmp/claude/doppler-secrets.cache"
mkdir -p /tmp/claude 2>/dev/null
SCOPES="${WAVE_DOPPLER_SCOPES:-wave/prd wave/stg}"

tmp="$(mktemp)" || exit 0
for scope in $SCOPES; do
  proj="${scope%%/*}"; cfg="${scope##*/}"
  [ -n "$proj" ] && [ -n "$cfg" ] || continue
  # --json prints name→value; we extract KEYS ONLY → values are never written anywhere.
  timeout 8 doppler secrets --json --project "$proj" --config "$cfg" 2>/dev/null \
    | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    for k in d: print(k)
except Exception:
    pass' 2>/dev/null \
    | while IFS= read -r n; do
        case "$n" in [A-Z]*) printf "%s\t%s/%s\n" "$n" "$proj" "$cfg" ;; esac
      done >> "$tmp"
done

if [ -s "$tmp" ]; then
  mv "$tmp" "$OUT" 2>/dev/null
  echo "[doppler] cached $(wc -l < "$OUT" | tr -d ' ') secret name(s) from: $SCOPES (guard active)"
else
  rm -f "$tmp" 2>/dev/null
fi
exit 0
