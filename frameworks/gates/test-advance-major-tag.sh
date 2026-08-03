#!/usr/bin/env bash
# Drill for scripts/advance-major-tag.sh — specifically the monotonicity guard (1b).
#
# WHAT THIS COVERS, AND WHAT IT DELIBERATELY DOES NOT.
# The guard runs BEFORE the expensive per-target self-test block (archive + emit.py + linters +
# workflow-policy), so every case here is decided before the script ever needs a real gate tree.
# That is the point: these scratch repos carry a stub `frameworks/gates/` and nothing else, so the
# forward/allowed cases are asserted as "got PAST the guard" (the target line printed, no refusal),
# not as an overall exit 0 — the script legitimately fails later for want of emit.py. Asserting a
# green exit here would be asserting something this fixture cannot produce.
#
# The REAL v1 tag is never touched. Everything happens in mktemp scratch repos with their own bare
# origin; the script's `git fetch origin` therefore talks to a local directory, not GitHub.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${WAVE_ADVANCE_SCRIPT:-$HERE/../../scripts/advance-major-tag.sh}"
[ -f "$SCRIPT" ] || { echo "cannot find advance-major-tag.sh at $SCRIPT" >&2; exit 2; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

pass=0; fail=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# Build a scratch repo whose v1 tag sits at $1 and whose newest release tag v1.9.0 sits at $2,
# both expressed as commit numbers in a 10-commit linear history. Echoes the repo path.
make_repo() { # $1=v1_at  $2=release_at  (commit indices, 1-based; 0 = do not create the v1 tag)
  local v1_at="$1" rel_at="$2"
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/amt.XXXXXX")"
  git init -q -b main "$d/repo"
  git -C "$d/repo" config user.email drill@wave.online
  git -C "$d/repo" config user.name drill
  mkdir -p "$d/repo/frameworks/gates" "$d/repo/scripts"
  local i
  for i in $(seq 1 10); do
    echo "$i" > "$d/repo/frameworks/gates/.keep"
    git -C "$d/repo" add -- frameworks/gates/.keep
    git -C "$d/repo" commit -q -m "c$i"
    eval "C$i=\$(git -C '$d/repo' rev-parse HEAD)"
  done
  eval "git -C '$d/repo' tag v1.9.0 \$C$rel_at"
  [ "$v1_at" = "0" ] || eval "git -C '$d/repo' tag v1 \$C$v1_at"
  cp "$SCRIPT" "$d/repo/scripts/advance-major-tag.sh"
  chmod +x "$d/repo/scripts/advance-major-tag.sh"
  git init -q --bare "$d/origin.git"
  git -C "$d/repo" remote add origin "$d/origin.git"
  git -C "$d/repo" push -q origin main --tags
  printf '%s' "$d"
}

# check <label> <repo> <expect-rc|any> <must-contain> [must-NOT-contain] [env assignment...]
check() {
  local label="$1" d="$2" want_rc="$3" want="$4" nowant="${5:-}"; shift 5 2>/dev/null || shift 4
  local out rc
  out="$(cd "$d/repo" && env "$@" bash scripts/advance-major-tag.sh v1 2>&1)"
  rc=$?   # straight off the command substitution — a pipeline here would report the wrong status
  local ok=1
  [ "$want_rc" = "any" ] || [ "$rc" = "$want_rc" ] || ok=0
  case "$out" in *"$want"*) :;; *) ok=0;; esac
  if [ -n "$nowant" ]; then case "$out" in *"$nowant"*) ok=0;; esac; fi
  if [ "$ok" = 1 ]; then
    pass=$((pass+1)); printf 'ok    %-52s rc=%s\n' "$label" "$rc"
  else
    fail=$((fail+1)); printf 'FAIL  %-52s rc=%s (want rc=%s)\n' "$label" "$rc" "$want_rc"
    printf '%s\n' "$out" | sed 's/^/        | /' | head -12
  fi
  rm -rf "$d"
}

echo "== advance-major-tag: monotonicity guard =="

# THE REGRESSION THIS EXISTS FOR: v1 ahead of the newest release tag. Pre-fix, all self-tests passed
# at the older tag and the script force-pushed v1 backward while printing a success line.
check "backward advance is REFUSED" \
  "$(make_repo 8 3)" 1 "REFUSING to move v1 backward" "now points at"

check "refusal names the distance" \
  "$(make_repo 8 3)" 1 "rewind the shared gate by 5 commit(s)" ""

# A deliberate rollback must stay possible — but only on purpose.
check "WAVE_ALLOW_TAG_REWIND=1 permits the rewind" \
  "$(make_repo 8 3)" any "moving v1 BACKWARD by 5 commit(s) on purpose" "REFUSING" \
  WAVE_ALLOW_TAG_REWIND=1

# Re-running after a successful advance must be a safe no-op, not an error.
check "tag already at target -> idempotent exit 0" \
  "$(make_repo 6 6)" 0 "already points at v1.9.0" "REFUSING"

# The normal, intended case: release tag ahead of the moving tag.
check "forward advance passes the guard" \
  "$(make_repo 3 8)" any "v1 would advance to v1.9.0" "REFUSING"

# First-ever advance: no tag to rewind, so the guard must not block it.
check "no existing v1 tag -> first advance allowed" \
  "$(make_repo 0 8)" any "does not exist yet" "REFUSING"

echo
if [ "$fail" -eq 0 ]; then
  echo "advance-major-tag self-test: ${pass} case(s) passed"
  exit 0
fi
echo "advance-major-tag self-test: ${fail} case(s) FAILED (${pass} passed)" >&2
exit 1
