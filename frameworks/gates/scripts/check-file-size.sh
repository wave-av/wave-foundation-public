#!/usr/bin/env bash
# check-file-size.sh — local mirror of the CI file-size gate (checks.yml / self-check.yml).
# Code files must stay <= MAX lines (default 800). Honors .github/.filesize-allowlist (one path per
# line) for justified exceptions, exactly like CI. Runs at pre-commit time so an oversized file is
# caught before it lands. Args: file paths (pre-commit passes staged matching files); with no args,
# scans git-tracked code files.
#
# THIS IS A MIRROR, AND A MIRROR THAT DISAGREES IS WORSE THAN NO MIRROR (#586 step 3). It was wrong
# in BOTH directions until 2026-07-29: it scanned only .ts/.tsx/.js/.py, so a 900-line .sh passed
# here and was blocked by CI; and it applied only the staging/ path exclude, so a 900-line dist/*.js
# was blocked here and exempt in CI. Keep the SCAN SET and the SKIP SET below byte-aligned with
# checks.yml's "File-size gate" step — scripts/gate-scope-conformance.mjs detects the drift.
set -euo pipefail

MAX="${FILE_SIZE_MAX:-800}"
ALLOWLIST=".github/.filesize-allowlist"

# SCAN SET (#586 step 3) — the SAME 18 extensions as checks.yml's file-size + token-budget gates,
# gen-token-budget-baseline.sh and token-budget-check-changed.sh. Held OUT: .vue/.cpp/.rs, the only
# extensions with pre-existing violations of the whole-tree line gate (#940).
SCAN_GLOBS=(
  '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.py' '*.go' '*.rb'
  '*.java' '*.kt' '*.swift' '*.c' '*.h' '*.cc' '*.sh' '*.bash' '*.svelte'
)
SCAN_RE='\.(ts|tsx|js|jsx|mjs|cjs|py|go|rb|java|kt|swift|c|h|cc|sh|bash|svelte)$'

# SKIP SET — vendored / generated material, exempt BY PATH exactly as in checks.yml (#586 step 2).
# Applied to the pre-commit ARGS path too: pre-commit hands us staged paths with no path filtering,
# which is how dist/*.js used to fail locally and pass in CI.
skip_path() {
  case "$1" in
    staging/* | dist/* | */dist/* | build/* | */build/* | *.min.js | \
    vendor/* | */vendor/* | external/* | */external/* | \
    third_party/* | */third_party/* | ThirdParty/* | */ThirdParty/* | \
    node_modules/* | */node_modules/*) return 0 ;;
  esac
  return 1
}

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  # A lister that FAILS is indistinguishable from one that found NOTHING — both leave the array
  # empty and print the ✓ line. Process substitution does not propagate status (and `pipefail`
  # cannot help through `< <(...)`), so run the enumerator first and check it explicitly.
  list=$(mktemp)
  trap 'rm -f "$list"' EXIT
  if ! git ls-files -- "${SCAN_GLOBS[@]}" >"$list"; then
    echo "file-size: ✗ git ls-files FAILED — refusing to report a pass" >&2
    exit 1
  fi
  # `grep -v` exiting 1 means "no lines selected", a legitimate empty result — filters keep `|| true`.
  while IFS= read -r f; do files+=("$f"); done < <(grep -vE '\.(types|d)\.ts$' "$list" || true)
fi

fail=0
# `"${files[@]}"` on an EMPTY array is an unbound-variable error under `set -u` in bash 3.2 (the
# macOS system bash this pre-commit hook runs under). Expand defensively.
for f in ${files[@]+"${files[@]}"}; do
  [ -f "$f" ] || continue
  printf '%s\n' "$f" | grep -qE "$SCAN_RE" || continue
  printf '%s\n' "$f" | grep -qE '\.(types|d)\.ts$' && continue
  skip_path "$f" && continue
  grep -qxF "$f" "$ALLOWLIST" 2>/dev/null && continue
  # `tr -d ' '`: BSD/macOS `wc` LEFT-PADS its count, GNU `wc` on the Linux runner does not — so the
  # same violation printed "has      900 lines" locally and "has 900 lines" in CI. Cosmetic, but this
  # file is a MIRROR whose value is agreeing with CI, and a padded number also breaks any grep an
  # author (or a drill) writes against the message.
  n=$(wc -l <"$f" | tr -d ' ')
  if [ "$n" -gt "$MAX" ]; then
    echo "file-size: ✗ $f has $n lines (> $MAX). Split it, or justify in $ALLOWLIST." >&2
    fail=1
  fi
done

[ "$fail" = 0 ] && echo "file-size: ✓ all code files <= $MAX lines"
exit "$fail"
