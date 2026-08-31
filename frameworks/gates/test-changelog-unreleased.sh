#!/usr/bin/env bash
# test-changelog-unreleased.sh — self-test for the PR-opening step in
# .github/workflows/changelog-unreleased.yml.
#
# WHAT IT PINS (#1028). The step used a per-SHA branch name, `chore/changelog-refresh-${SHA::7}`,
# so every merge to main produced a DISTINCT branch, therefore a DISTINCT pull request, and nothing
# ever closed the previous one. Fourteen open changelog PRs accumulated in about two days. Each
# carried a full ~60 check-run matrix and each fired its own org-wide license-policy-audit — the
# very secondary-rate-limit pressure #1031 had just engineered out of that audit. The workflow was
# "working" the entire time: nothing failed, nothing was red, and the cost was invisible because it
# landed on OTHER PRs' check budgets rather than on this workflow's own result.
#
# So the property under test is not "does it succeed" — it always did. It is:
#   1. the branch name does NOT vary with the commit SHA, and
#   2. a second run UPDATES the standing PR instead of opening another.
# A test that only asserted exit 0 would have passed against the broken version.
#
# HOW. The step body is EXTRACTED from the workflow with PyYAML at run time, never re-typed here —
# a re-typed copy is a second implementation that can agree with this test while disagreeing with
# what CI actually runs. Network-touching commands are stubbed on PATH: `gh` entirely, and `git`
# only for `push` (every other git subcommand is forwarded to the real binary, so `switch`,
# `commit` and `diff` exercise real git in a throwaway repo).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORKFLOW="${WAVE_CHANGELOG_WORKFLOW:-$ROOT/.github/workflows/changelog-unreleased.yml}"
[ -f "$WORKFLOW" ] || { echo "error: workflow not found at $WORKFLOW" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0
pass() { printf '  ok   %s\n' "$1"; }
# On failure, show the step's own output too — the call log says WHAT was invoked, but when the
# step dies early (a bad interpolation, a missing binary) the reason is only in its stderr.
fail() {
  printf '  FAIL %s\n' "$1"
  printf '%s\n' "${RUN_OUT:-}" | tail -8 | sed 's/^/        | /'
  fails=$((fails + 1))
}

# --- extract the step body -----------------------------------------------------------------------
STEP="$work/changelog-step.sh"
if ! python3 - "$WORKFLOW" "$STEP" <<'PY'
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
steps = [s for j in yaml.safe_load(open(wf, encoding='utf-8'))['jobs'].values()
         for s in (j.get('steps') or [])
         if 'Open auto-merge PR' in str(s.get('name', ''))]
if len(steps) != 1:
    sys.exit(f"expected exactly 1 PR-opening step, found {len(steps)}")
open(out, 'w', encoding='utf-8').write(steps[0]['run'])
PY
then
  echo "  FAIL could not extract the PR-opening step from $WORKFLOW"
  exit 1
fi
pass "extracted the PR-opening step from changelog-unreleased.yml"

# --- stubs ---------------------------------------------------------------------------------------
# `gh` records every invocation and answers the three queries the step makes. EXISTING_PR drives the
# create-or-update fork: empty means "no open PR for this head".
#
# `gh pr list --json number -q '.[0].number'` on an EMPTY list prints NOTHING, not the string
# "null" — verified against real gh 2.x before writing this stub. That distinction is the whole
# guard: were it to print "null", `[ -z "$prnum" ]` would be false, the step would skip creating
# the PR and then try to label PR "null". A stub that got this wrong would silently bless a broken
# guard, so it is modelled rather than guessed.
make_stubs() {
  local bin="$1"
  mkdir -p "$bin"
  cat >"$bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >>"$GH_CALLLOG"
case "$1 $2" in
  "pr list")
    if [ -n "${EXISTING_PR:-}" ]; then echo "$EXISTING_PR"; fi   # empty output when none
    exit 0 ;;
  "pr create")
    echo "https://github.com/wave-av/wave-foundation/pull/${NEW_PR:-9001}"
    exit 0 ;;
  "pr view")
    echo "${NEW_PR:-9001}"
    exit 0 ;;
  "api "*|"api")
    exit 0 ;;
esac
exit 0
STUB
  # Forward everything to the real git EXCEPT `push`, which would hit the network. Recording the
  # push lets the drill assert the branch name and the --force flag, which is where the defect was.
  cat >"$bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "push" ]; then
  echo "git $*" >>"$GH_CALLLOG"
  exit 0
fi
exec /usr/bin/env -u PATH_STUB "$REAL_GIT" "$@"
STUB
  chmod +x "$bin/gh" "$bin/git"
}

# Build a throwaway repo whose CHANGELOG.md differs from HEAD, so the step gets past its
# `git diff --quiet` early-exit and reaches the branch/push/PR logic.
new_repo() {
  local d="$1" changed="$2"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  printf '# Changelog\n\n## [unreleased]\n\n- old\n' >"$d/CHANGELOG.md"
  git -C "$d" add CHANGELOG.md
  git -C "$d" commit -qm init
  if [ "$changed" = yes ]; then
    printf '# Changelog\n\n## [unreleased]\n\n- old\n- NEW ENTRY\n' >"$d/CHANGELOG.md"
  fi
}

# Run the extracted step inside $d with the given SHA. Echoes nothing; sets RUN_OUT / RUN_RC / LOG.
run_step() {
  local d="$1" sha="$2"
  LOG="$d/.calls"
  : >"$LOG"
  local bin="$d/.bin"
  make_stubs "$bin"
  RUN_OUT="$(cd "$d" && env PATH="$bin:$PATH" \
    REAL_GIT="$REAL_GIT" GH_CALLLOG="$LOG" \
    EXISTING_PR="${EXISTING_PR:-}" NEW_PR="${NEW_PR:-9001}" \
    GH_TOKEN=stub-token GITHUB_REPOSITORY=wave-av/wave-foundation GITHUB_SHA="$sha" \
    bash -e "$STEP" 2>&1)"
  RUN_RC=$?
}

REAL_GIT="$(command -v git)"

# --- cases ---------------------------------------------------------------------------------------
echo "== changelog-unreleased: one standing PR, updated in place =="

# A. Nothing to do — the changelog is already current. Must exit 0 and touch no PR at all.
d="$work/a"; new_repo "$d" no
EXISTING_PR="" run_step "$d" aaaaaaaaaaaa
if [ "$RUN_RC" -eq 0 ] && ! grep -q '^gh ' "$LOG"; then
  pass "A  changelog already current       -> exits 0, opens nothing"
else
  fail "A  changelog already current       -> rc=$RUN_RC, calls: $(tr '\n' ';' <"$LOG")"
fi

# B. No standing PR yet -> create exactly one.
d="$work/b"; new_repo "$d" yes
EXISTING_PR="" NEW_PR=4242 run_step "$d" bbbbbbbbbbbb
creates="$(grep -c '^gh pr create' "$LOG" || true)"
if [ "$RUN_RC" -eq 0 ] && [ "$creates" = 1 ] && grep -q 'issues/4242/labels' "$LOG"; then
  pass "B  no standing PR                  -> creates exactly 1, labels it"
else
  fail "B  no standing PR                  -> rc=$RUN_RC creates=$creates log: $(tr '\n' ';' <"$LOG")"
fi

# C. THE REGRESSION. A standing PR already exists -> must NOT open a second one. This is the case
# the per-SHA branch could never reach, because each run's head branch was unique by construction.
d="$work/c"; new_repo "$d" yes
EXISTING_PR=4242 run_step "$d" cccccccccccc
creates="$(grep -c '^gh pr create' "$LOG" || true)"
if [ "$RUN_RC" -eq 0 ] && [ "$creates" = 0 ] && grep -q 'issues/4242/labels' "$LOG"; then
  pass "C  standing PR exists              -> updates it, opens NO second PR"
else
  fail "C  standing PR exists              -> rc=$RUN_RC creates=$creates (want 0), log: $(tr '\n' ';' <"$LOG")"
fi

# D. THE ROOT CAUSE, pinned directly: the branch name must not vary with the commit SHA. Two runs
# at different SHAs must push the SAME ref. Under the old `chore/changelog-refresh-${SHA::7}` this
# is the assertion that fails, and it is the only one that names the actual defect.
d="$work/d1"; new_repo "$d" yes
EXISTING_PR="" run_step "$d" 1111111111111111
ref1="$(sed -n 's/.*HEAD:\(.*\)$/\1/p' "$LOG" | head -1)"
d="$work/d2"; new_repo "$d" yes
EXISTING_PR="" run_step "$d" 2222222222222222
ref2="$(sed -n 's/.*HEAD:\(.*\)$/\1/p' "$LOG" | head -1)"
if [ -n "$ref1" ] && [ "$ref1" = "$ref2" ]; then
  pass "D  branch name is SHA-independent  -> both runs push $ref1"
else
  fail "D  branch name is SHA-independent  -> run1 pushed '$ref1', run2 pushed '$ref2'"
fi

# E. A stable branch is only workable if the push can overwrite it — the second run's history is
# not a descendant of the first's, so a non-forced push would be rejected as non-fast-forward and
# the refresh would silently stop happening after the first merge.
if grep -q '^git push --force' "$LOG"; then
  pass "E  push is forced                  -> a stable branch can actually be updated"
else
  fail "E  push is forced                  -> $(grep '^git push' "$LOG" | head -1)"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "changelog-unreleased self-test: all cases pass"
  exit 0
fi
echo "changelog-unreleased self-test: $fails case(s) FAILED"
exit 1
