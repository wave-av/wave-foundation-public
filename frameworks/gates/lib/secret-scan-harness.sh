#!/usr/bin/env bash
# secret-scan-harness.sh — shared by the test-secret-scan-*.sh suites, sourced rather than run.
#
# Every case runs the REAL script or the block EXTRACTED from the workflow against a throwaway tree
# under a mktemp dir. Fake values are assembled at run time, so this file holds no credential shape.
# The sourcing suite sets its own `set -uo pipefail`.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
GATE="$HERE/scripts/secret-scan.sh"
WORKFLOW="$REPO/.github/workflows/checks.yml"

work="$(mktemp -d)" || { echo "error: cannot create a work directory"; exit 1; }
trap 'rm -rf "$work"' EXIT
inline_block="$work/checks-inline.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

python3 - "$WORKFLOW" "$inline_block" <<'PY' || { echo "error: cannot extract the Secret scan step"; exit 1; }
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
steps = [s for j in yaml.safe_load(open(wf, encoding='utf-8'))['jobs'].values()
         for s in (j.get('steps') or []) if 'Secret scan' in str(s.get('name', ''))]
if len(steps) != 1:
    sys.exit(f"expected exactly 1 'Secret scan' step in checks.yml, found {len(steps)}")
open(out, 'w', encoding='utf-8').write(steps[0]['run'])
PY

no_ci_env=(env -u GITHUB_EVENT_NAME -u PR_BASE_SHA -u PR_HEAD_SHA -u MERGE_BASE_SHA)
gate_env=("${no_ci_env[@]}")
run_script() { (cd "$1" && "${gate_env[@]}" bash "$GATE" 2>&1); }
# `bash -e`: GitHub runs a `run:` block that way, and it is the difference between the two copies.
run_inline() { (cd "$1" && "${gate_env[@]}" bash -e "$inline_block" 2>&1); }

# check_one <case> <runner> <want_exit> <want_text> <tree>
check_one() {
  local name="$1" runner="$2" want_exit="$3" want_text="$4" tree="$5" out rc
  out="$("$runner" "$tree")"; rc=$?
  if [ "$rc" -ne "$want_exit" ]; then
    fail "$name — exit $rc, want $want_exit"
    printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
  elif [[ "$out" != *"$want_text"* ]]; then
    fail "$name — exit $rc correct, but output never says '$want_text'"
    printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
  else
    pass "$name"
  fi
}

# both <case> <want_exit> <want_text> <tree> — the two copies must agree.
both() {
  check_one "$1 [script]" run_script "$2" "$3" "$4"
  check_one "$1 [workflow]" run_inline "$2" "$3" "$4"
}

# never_prints <case> <value> <tree> — a finding's output must not contain <value>.
never_prints() {
  local out runner
  for runner in run_script run_inline; do
    out="$("$runner" "$3")"
    if [[ "$out" == *"$2"* ]]; then fail "$1 [$runner] — output contains the matched text"; else pass "$1 [$runner]"; fi
  done
}

canary="AKIA$(printf 'ABCDEFGHIJKLMNOP')"

# shape_tree <name> <line> — a scan root holding <line> in src/config.js, with no allowlist.
shape_tree() {
  local d="$work/$1"
  mkdir -p "$d/src"
  printf '%s\n' "$2" > "$d/src/config.js"
  printf '%s' "$d"
}

git_t() {
  local d="$1"; shift
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$d" \
    -c user.name=gate-test -c user.email=gate-test@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1
}

# pr_tree <name> — a repo whose one commit holds a listed file and a pragma-tagged line. That commit
# is the base of the "pull request"; each case then changes the working tree on top of it.
pr_tree() {
  local d="$work/$1"
  mkdir -p "$d/.github" "$d/src" "$d/docs"
  printf '# exceptions\ndocs/EXAMPLE.md\n' > "$d/.github/.secret-allowlist"
  printf 'key: %s\n' "$canary" > "$d/docs/EXAMPLE.md"
  printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$d/src/fixture.js"
  printf 'hello\n' > "$d/src/app.js"
  git_t "$d" init -q --template=
  git_t "$d" add -A
  git_t "$d" commit -q -m base
  printf '%s' "$d"
}
on_pr()    { gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=pull_request PR_BASE_SHA="$1"); }
on_queue() { gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=merge_group MERGE_BASE_SHA="$1"); }
base_of()  { git -C "$1" rev-parse HEAD; }

# plant <tree> <path> — puts a key shape in <path>, creating its parents.
plant() {
  mkdir -p "$1/$(dirname "$2")"
  printf 'const k = "%s";\n' "$canary" > "$1/$2"
}

# pr_tree_with <name> <entry> [<file>] — pr_tree, with one more entry and a harmless <file> on the base.
pr_tree_with() {
  local d
  d="$(pr_tree "$1")"
  printf '%s\n' "$2" >> "$d/.github/.secret-allowlist"
  if [ -n "${3:-}" ]; then
    mkdir -p "$d/$(dirname "$3")"
    printf 'hello\n' > "$d/$3"
  fi
  git_t "$d" add -A
  git_t "$d" commit -q -m entry
  printf '%s' "$d"
}

# finish <suite name> — prints the verdict and exits with it.
finish() {
  echo
  if [ "$fails" -eq 0 ]; then
    echo "$1 self-test: all cases pass"
    exit 0
  fi
  echo "$1 self-test: $fails case(s) FAILED"
  exit 1
}
