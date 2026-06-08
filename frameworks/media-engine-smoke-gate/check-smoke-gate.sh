#!/usr/bin/env bash
# Media-engine smoke-gate meta-check (ADVISORY — never fails the build).
#
# The blocking guarantee is each repo's own CI step:  ./engine/wave-x-test | grep -q "WAVE X TEST PASS"
# This script is the meta-check that those sentinel-greps EXIST for every test the build produces — so
# the gate can't rot by someone adding a test binary to the build but forgetting to assert its PASS line.
#
# It cross-references:
#   - test executables produced by a build file  (default: build.sh)  — pattern  -o .../wave-<name>-test
#   - sentinel assertions in a CI workflow        (default: .github/workflows/engine-ci.yml)
#                                                   — pattern  grep -q "WAVE ... TEST PASS"
# and warns about any built-but-unasserted test. Exit 0 always; prints a summary. Dependency-free (grep/sed).
#
# Usage: check-smoke-gate.sh [BUILD_FILE] [CI_FILE]
set -uo pipefail
BUILD="${1:-build.sh}"
CI="${2:-.github/workflows/engine-ci.yml}"

if [ ! -f "$BUILD" ]; then echo "smoke-gate: no build file at '$BUILD' — skipping (not a media-engine repo?)"; exit 0; fi
if [ ! -f "$CI" ]; then echo "smoke-gate: no CI file at '$CI' — skipping"; exit 0; fi

# Test binaries the build produces: tokens like wave-<something>-test after a -o flag.
built=$(grep -oE '\-o "?\$?[A-Za-z0-9_/{}.-]*wave-[a-z0-9-]+-test' "$BUILD" 2>/dev/null \
        | grep -oE 'wave-[a-z0-9-]+-test' | sort -u)
# Tests asserted with a PASS sentinel in CI.
asserted=$(grep -oE 'wave-[a-z0-9-]+-test' "$CI" 2>/dev/null | sort -u)

miss=0
total=0
for t in $built; do
  total=$((total+1))
  if ! printf '%s\n' "$asserted" | grep -qx "$t"; then
    echo "::warning::smoke-gate: '$t' is built by $BUILD but has NO sentinel grep in $CI (built-but-unasserted)"
    miss=$((miss+1))
  fi
done

# Also flag CI lines that RUN a test but carry no sentinel grep on that line.
while IFS= read -r line; do
  printf '%s\n' "$line" | grep -q 'wave-[a-z0-9-]\+-test' || continue   # line doesn't run a test
  printf '%s\n' "$line" | grep -q 'grep' && continue                    # has a grep — assume sentinel
  tname=$(printf '%s\n' "$line" | grep -oE 'wave-[a-z0-9-]+-test' | head -1)
  echo "::warning::smoke-gate: CI line runs '${tname:-a test}' without a 'grep -q \"WAVE … TEST PASS\"' sentinel"
done < "$CI"

if [ "$total" -eq 0 ]; then
  echo "smoke-gate: no 'wave-*-test' binaries found in $BUILD (nothing to check)"
elif [ "$miss" -eq 0 ]; then
  echo "smoke-gate OK: all $total built smoke(s) are sentinel-asserted in CI"
else
  echo "smoke-gate: $miss of $total built smoke(s) lack a CI sentinel assertion (advisory — see warnings above)"
fi
exit 0
