#!/usr/bin/env bash
# verify-vendored.sh — the CI hash-check the edge-proxy standard prescribes.
#
# A surface that adopts the thin-proxy chassis COPIES proxy.ts/route.ts/cache.ts into its src/ and
# replaces the four placeholders (__ORIGIN_URL__/__PRODUCT__/__PROTOCOL__/__SPOKE_NAME__) with its
# own values. This script proves that copy has NOT drifted from the foundation reference: it applies
# the surface's four substitutions to the reference and diffs the result against the vendored copy.
# Any difference beyond those four substitutions is the copy-paste drift this framework exists to kill.
#
# Run it from the surface's CI (the reference travels in via consume.sh's pinned .foundation/ copy).
#
# Usage:
#   verify-vendored.sh --vendored <dir> \
#     --origin-url <v> --product <v> --protocol <v> --spoke-name <v> [--ref <dir>]
#
#   --vendored   dir holding the surface's copy of proxy.ts/route.ts/cache.ts (e.g. src/)
#   --origin-url --product --protocol --spoke-name  the four substitutions the surface applied
#                (the literal text it put in place of each placeholder)
#   --ref        the edge-proxy reference dir (default: this script's ./reference)
#
# Exit: 0 = in sync · 1 = drift found · 2 = setup error (treat as fail-closed).
set -uo pipefail

REF="$(cd "$(dirname "$0")" && pwd)/reference"
VENDORED=""
ORIGIN_URL="" PRODUCT="" PROTOCOL="" SPOKE_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --vendored) VENDORED="${2:-}"; shift 2 ;;
    --ref) REF="${2:-}"; shift 2 ;;
    --origin-url) ORIGIN_URL="${2:-}"; shift 2 ;;
    --product) PRODUCT="${2:-}"; shift 2 ;;
    --protocol) PROTOCOL="${2:-}"; shift 2 ;;
    --spoke-name) SPOKE_NAME="${2:-}"; shift 2 ;;
    *) echo "::error::unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$VENDORED" ] || { echo "::error::--vendored <dir> is required" >&2; exit 2; }
[ -d "$VENDORED" ] || { echo "::error::vendored dir not found: $VENDORED" >&2; exit 2; }
[ -d "$REF" ] || { echo "::error::reference dir not found: $REF (pass --ref)" >&2; exit 2; }
for v in ORIGIN_URL PRODUCT PROTOCOL SPOKE_NAME; do
  eval "val=\${$v}"
  # shellcheck disable=SC2154
  [ -n "$val" ] || { echo "::error::--$(echo "$v" | tr 'A-Z_' 'a-z-') is required (the surface's substitution for __${v}__)" >&2; exit 2; }
done

# Substitute the surface's four values into the reference, then diff vs the vendored copy.
subst() {
  sed -e "s|__ORIGIN_URL__|${ORIGIN_URL}|g" \
      -e "s|__PRODUCT__|${PRODUCT}|g" \
      -e "s|__PROTOCOL__|${PROTOCOL}|g" \
      -e "s|__SPOKE_NAME__|${SPOKE_NAME}|g" "$1"
}

drift=0
for f in proxy.ts route.ts cache.ts; do
  if [ ! -f "$VENDORED/$f" ]; then
    echo "MISSING: $VENDORED/$f — the surface must vendor all three chassis files" >&2
    drift=1
    continue
  fi
  if ! diff -u <(subst "$REF/$f") "$VENDORED/$f" >/tmp/edge-proxy-drift.diff 2>/dev/null; then
    echo "DRIFT: $f differs from the edge-proxy reference (beyond the four placeholder substitutions):" >&2
    sed 's/^/    /' /tmp/edge-proxy-drift.diff >&2
    drift=1
  fi
done

rm -f /tmp/edge-proxy-drift.diff
if [ "$drift" = 0 ]; then
  echo "✓ vendored edge-proxy chassis matches the reference (modulo placeholders)"
  exit 0
fi
echo "✗ vendored edge-proxy chassis has drifted — re-vendor from frameworks/edge-proxy/reference/." >&2
exit 1
