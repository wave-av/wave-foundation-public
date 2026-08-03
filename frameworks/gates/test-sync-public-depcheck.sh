#!/usr/bin/env bash
# Drill for the pre-publish dependency check in scripts/sync-public.sh (scanner 3).
#
# Scanner 3 answers "does a file we are about to publish CALL something that stays
# private?" Getting it wrong is expensive in both directions:
#   - too loose  -> missing_dep_count > 0 blocks every publish on noise, and people
#                   learn to ignore the list (it already cried wolf once at 12 hits);
#   - too strict -> a published gate ships with its helper still private and the
#                   public suite can only fail (5 gate-self-tests at once, #1225).
# So the discrimination between "invokes it" and "merely names it" IS the gate, and
# it is regex-shaped, which is exactly the kind of thing that rots silently.
#
# Mirror guard: sync-public.sh is the publisher and deliberately does NOT publish, so
# on the public mirror there is nothing to test. Skip cleanly rather than exit 2 --
# that failure mode is the very bug this file exists to prevent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/../.."
# Guard NAMES the file it protects, rather than a variable holding it: that is the form
# the dep-check recognises, and it is the one a reader can check without tracing a var.
[ -f "$ROOT/scripts/sync-public.sh" ] || { echo "::notice::sync-public.sh absent (public mirror) — skipping"; exit 0; }
SYNC="${WAVE_SYNC_PUBLIC:-$ROOT/scripts/sync-public.sh}"

pass=0 fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# Build a throwaway repo whose layout matches the allowlist: anything tracked under
# frameworks/ publishes, and scripts/private-helper.sh does not.
fixture() {
  local d="$1" published_body="$2" ext="${3:-sh}"
  mkdir -p "$d/frameworks/gates" "$d/scripts"
  printf '%s\n' "$published_body" > "$d/frameworks/gates/test-fixture.$ext"
  printf '#!/usr/bin/env bash\necho helper\n' > "$d/scripts/private-helper.sh"
  cp "$SYNC" "$d/scripts/sync-public.sh"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm fixture
}

# Returns the audit's machine-readable count for a given published-file body.
count_for() {
  local d body ext
  body="$1"
  ext="${2:-sh}"
  d="$(mktemp -d)"
  fixture "$d" "$body" "$ext"
  ( cd "$d" && bash scripts/sync-public.sh 2>/dev/null || true ) \
    | grep -oE '^missing_dep_count=[0-9]+' | tail -1 | cut -d= -f2
  rm -rf "$d"
}

expect() {
  local label="$1" want="$2" body="$3" ext="${4:-sh}" got
  got="$(count_for "$body" "$ext")"
  [ "$got" = "$want" ] && ok "$label (count=$got)" || bad "$label: expected $want, got ${got:-<none>}"
}

echo "sync-public dep-check drill"

# --- POSITIVE: the shapes that broke the mirror, all variable-rooted ---
expect "A  plain \$VAR assignment is a dependency" 1 \
  'GATE="$REPO_ROOT/scripts/private-helper.sh"'

expect "B  \${VAR:-default} keeps the path INSIDE the braces" 1 \
  'S="${WAVE_X:-$HERE/../../scripts/private-helper.sh}"'

expect "C  interpreter invocation at command position" 1 \
  'bash "$ROOT/scripts/private-helper.sh" --flag'

# A sourced lib is the strictest dependency of all: no guard is possible, the caller
# just dies. Both spellings must count.
expect "I  source is a dependency" 1 \
  'source "$HERE/../../scripts/private-helper.sh"'

expect "J  the . spelling of source counts too" 1 \
  '. "$HERE/../../scripts/private-helper.sh"'

# A `case` default branch begins with `*`, which is a COMMENT only in JS. Stripping it
# from shell discards real work, and a helper reached only through a fallback would
# publish clean and then die on the mirror.
expect "K  a case-default branch is real work, not a comment" 1 \
  'case "$x" in
  ok) echo fine ;;
  *) bash "$ROOT/scripts/private-helper.sh" ;;
esac'

# An executable helper needs no interpreter word at all.
expect "L  a directly-executed path counts" 1 \
  '"$ROOT/scripts/private-helper.sh" --dry-run'

expect "M  a function-local assignment still counts" 1 \
  '  local GATE="$ROOT/scripts/private-helper.sh"'

# .ts publishes (116 files under the allowlist) and was omitted from the file-type
# selector while the comment-stripper and extension regex both already handled it.
expect "N  .ts files are scanned, not just .sh/.mjs/.js/.py" 1 \
  'execSync("bash scripts/private-helper.sh");' ts

# JS/TS comments are // and *, NOT # -- a `#` line there is real code (a private field).
expect "O  a JS comment is stripped in .ts" 0 \
  '// see scripts/private-helper.sh for details' ts

# --- NEGATIVE: named but not load-bearing. Each of these was a real false hit. ---
expect "D  prose inside a message is NOT a dependency" 0 \
  'echo "this tree is mirrored publicly (scripts/private-helper.sh)."'

expect "E  a shell comment is NOT a dependency" 0 \
  '# see scripts/private-helper.sh for details'

# The `sh` alternation must be anchored to a command position: unanchored, it matches
# the TAIL of "private-helper.sh " and every mention becomes an invocation.
expect "F  '.sh ' tail does not read as an 'sh' invocation" 0 \
  'echo "then run: scripts/private-helper.sh <id> --reviewer <who>"'

# The sanctioned escape hatch: a job that guards for the mirror is handled, not missing.
expect "G  a repo-root literal guard suppresses the report" 0 \
  'S="$ROOT/scripts/private-helper.sh"
[ -f scripts/private-helper.sh ] || { echo "::notice::absent — skipping"; exit 0; }'

# A workflow runs from the repo root and can guard a literal; a SCRIPT cannot assume
# its cwd and must root the path. Recognising only the literal would force script
# authors to write a guard that does not work -- and this very file, which guards its
# own use of sync-public.sh, was the first thing to hit it.
expect "H  a \$ROOT-rooted guard is recognised too" 0 \
  '[ -f "$ROOT/scripts/private-helper.sh" ] || { echo "::notice::absent — skipping"; exit 0; }
S="$ROOT/scripts/private-helper.sh"'

echo "  ---"
if [ "$fail" -ne 0 ]; then
  echo "sync-public dep-check drill FAILED ($fail of $((pass + fail)))" >&2
  exit 1
fi
echo "sync-public dep-check drill passed ($pass/$pass)"
