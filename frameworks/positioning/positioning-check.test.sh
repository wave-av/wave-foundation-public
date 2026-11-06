#!/usr/bin/env bash
# Fixture-driven red/green test for positioning-check.sh (wave-foundation#1454).
# Each fixture is a single line written to a real .md file (a real is_target() surface) and run
# through the gate directly (not --staged/--changed, so no git state is required). A RED fixture
# must exit non-zero (>=1 ERROR); a GREEN fixture must exit 0 (0 errors — warnings are fine).
#
# Usage: bash frameworks/positioning/positioning-check.test.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gate="$here/positioning-check.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0

# assert_red <name> <line>   — the line must produce a FAIL (exit != 0).
assert_red() {
  local name="$1"
  local line="$2"
  local file="$tmp/$name.md"
  printf '%s\n' "$line" > "$file"
  if bash "$gate" "$file" >/dev/null 2>&1; then
    echo "FAIL (expected RED/ERROR, got PASS): $name — '$line'"; fail=$((fail+1))
  else
    echo "ok (RED as expected): $name"; pass=$((pass+1))
  fi
}

# assert_green <name> <line> — the line must produce a PASS (exit == 0).
assert_green() {
  local name="$1"
  local line="$2"
  local file="$tmp/$name.md"
  printf '%s\n' "$line" > "$file"
  if bash "$gate" "$file" >/dev/null 2>&1; then
    echo "ok (GREEN as expected): $name"; pass=$((pass+1))
  else
    echo "FAIL (expected GREEN/PASS, got ERROR): $name — '$line'"; fail=$((fail+1))
  fi
}

echo "# 1454 finding 2 — SOC 2 exclusion scoped to the claim, not the whole line"
assert_red  soc2-like-vendor        "We're SOC 2 like Cloudflare."
assert_green soc2-attributed-vendor "Cloudflare is SOC 2 Type II certified for its infrastructure; WAVE itself holds no SOC 2 attestation."

echo "# 1454 finding 3 — 'Type II' is not a safe term on its own"
assert_red  soc2-typeii-unattributed "WAVE is SOC 2 Type II certified."
assert_green soc2-explicit-negation  "WAVE holds no SOC 2 attestation."

echo "# gitar-bot review on #1457 — trailing window must reach a vendor named a few words later"
assert_green soc2-vendor-few-words-later "Our vendor maintains SOC 2 compliance, including Cloudflare and Stripe attestations."

echo "# 1454 finding 4 — capability-first headline beyond 'WAVE is'"
assert_red  headline-colon "WAVE: a video API for agents."
assert_red  headline-dash  "WAVE — a video API for agents."
assert_red  headline-comma "WAVE, a video API for agents."
assert_green identity-lead "WAVE is media infrastructure for the agentic internet."

echo "—"
echo "positioning-check.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
