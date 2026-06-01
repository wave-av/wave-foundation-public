#!/usr/bin/env bash
# check-file-size.sh — local mirror of the CI file-size gate (checks.yml / self-check.yml).
# Code files must stay <= MAX lines (default 800). Honors .github/.filesize-allowlist (one path per
# line) for justified exceptions, exactly like CI. Runs at pre-commit time so an oversized file is
# caught before it lands. Args: file paths (pre-commit passes staged matching files); with no args,
# scans git-tracked code files.
set -euo pipefail

MAX="${FILE_SIZE_MAX:-800}"
ALLOWLIST=".github/.filesize-allowlist"

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  # No-args scan honors the same staging/ FIDELITY exclude the pre-commit global config applies to
  # every hook, so standalone behavior matches how this runs under pre-commit.
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files '*.ts' '*.tsx' '*.js' '*.py' | grep -vE '\.(types|d)\.ts$' | grep -vE '^staging/')
fi

fail=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  printf '%s\n' "$f" | grep -qE '\.(ts|tsx|js|py)$' || continue
  printf '%s\n' "$f" | grep -qE '\.(types|d)\.ts$' && continue
  grep -qxF "$f" "$ALLOWLIST" 2>/dev/null && continue
  n=$(wc -l <"$f")
  if [ "$n" -gt "$MAX" ]; then
    echo "file-size: ✗ $f has $n lines (> $MAX). Split it, or justify in $ALLOWLIST." >&2
    fail=1
  fi
done

[ "$fail" = 0 ] && echo "file-size: ✓ all code files <= $MAX lines"
exit "$fail"
