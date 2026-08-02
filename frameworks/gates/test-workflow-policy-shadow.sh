#!/usr/bin/env bash
# test-workflow-policy-shadow.sh — self-test for the SHADOW half of the WAS workflow-policy lint
# inlined in .github/workflows/checks.yml (step "Workflow-policy enforce").
#
# Split out of test-workflow-policy.sh when rule9 (#1020) pushed that file past the ~6000-token hard
# gate. The seam is a real one: a SHADOW rule emits ::notice::WAS-SHADOW and exits 0, which is the
# exact opposite of what the sibling suite's enforce loop asserts (exit 1 + exactly one ::error::),
# so shadow fixtures could never have lived in that loop anyway — they were already in their own
# dedicated sections, per #886. This file is those sections.
#
#   test-workflow-policy.sh        — ENFORCE path + the rule registry's structure/provenance
#   test-workflow-policy-shadow.sh — THIS FILE: shadow rules' fixtures + canary-enforce routing
#
# Note on the promotion brake: test-human-review-gate.sh and test-confidence-calibration-gate.sh
# re-run test-workflow-policy.sh internally before a rule promotion. That stays correct after the
# split — what a promotion must not break is the severity/provenance structure, which lives in the
# sibling. This suite is discovered and run on its own by the gate-self-tests job's
# `git ls-files 'frameworks/gates/test-*.sh'` glob.
#
# shellcheck disable=SC2154
# ^ work/lint_py/FIXTURES are assigned by the harness sourced below. The source= directive on that
# line says where to look, but it is only acted on under -x, which the repo's shell ratchet does not
# pass — so without this suppression the ratchet reports every harness-provided variable unassigned.
# (Keep every continuation line from starting with the literal directive prefix: any comment opening
# that way is parsed AS a directive, which is SC1072 "expected = after directive key".)
set -euo pipefail

# shellcheck source=lib/workflow-policy-harness.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workflow-policy-harness.sh"

fail=0

# --- rule8 (SHADOW): push+pull_request double-run fixtures ---
# Each fixture is staged as `.shadow-staged` (excluded from the sibling suite's `bad-rule*.yml`
# glob) until rule8 is ever promoted.
rule8_marker() {
  case "$1" in
    bad-rule8-push-staging-and-main.yml.shadow-staged) echo "isn't scoped to ONLY merge-target branch(es)" ;;
    bad-rule8-branches-ignore.yml.shadow-staged)        echo "isn't scoped to ONLY merge-target branch(es)" ;;
    bad-rule8-bare-push.yml.shadow-staged)              echo "isn't scoped to ONLY merge-target branch(es)" ;;
    *) echo "" ;;
  esac
}
for staged in "$FIXTURES"/bad-rule8-*.yml.shadow-staged; do
  [ -f "$staged" ] || continue
  name="$(basename "$staged")"
  marker="$(rule8_marker "$name")"
  target_name="$(basename "$staged" .shadow-staged)"
  dir="$work/rule8-$(basename "$staged" .yml.shadow-staged)"
  mkdir -p "$dir/.github/workflows"
  cp "$staged" "$dir/.github/workflows/$target_name"
  set +e; out="$(cd "$dir" && env -u GITHUB_REPOSITORY python3 "$lint_py" 2>&1)"; rc=$?; set -e
  errs="$(printf '%s\n' "$out" | grep -c '^::error::' || true)"
  notices="$(printf '%s\n' "$out" | grep -c '^::notice::WAS-SHADOW rule=rule8' || true)"
  if [ "$rc" -ne 0 ] || [ "$errs" -ne 0 ] || [ "$notices" -ne 1 ]; then
    echo "FAIL $name: expected exit 0 / 0 errors / 1 rule8 shadow notice, got exit=$rc errors=$errs notices=$notices"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  elif ! printf '%s\n' "$out" | grep -qF "$marker"; then
    echo "FAIL $name: expected the rule8 shadow notice to mention '$marker'"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  else
    echo "PASS $name (exit 0, 0 errors, rule8 shadow notice fired: '$marker')"
  fi
done

# --- rule9 (SHADOW): cancel-in-progress + same-head-SHA re-fire fixtures (#1020) ---
# Each fixture is one of the three shapes actually found in this repo, so a regression in the
# predicate fails here naming the real workflow it came from.
rule9_marker() {
  case "$1" in
    bad-rule9-pr-edited.yml.shadow-staged)     echo "pull_request:edited" ;;
    bad-rule9-pr-labeled.yml.shadow-staged)    echo "pull_request:labeled,ready_for_review" ;;
    bad-rule9-review-events.yml.shadow-staged) echo "issue_comment, pull_request_review, pull_request_review_comment" ;;
    *) echo "" ;;
  esac
}
for staged in "$FIXTURES"/bad-rule9-*.yml.shadow-staged; do
  [ -f "$staged" ] || continue
  name="$(basename "$staged")"
  marker="$(rule9_marker "$name")"
  if [ -z "$marker" ]; then
    echo "FAIL $name: no expected marker registered — add one to rule9_marker()"
    fail=1
    continue
  fi
  target_name="$(basename "$staged" .shadow-staged)"
  dir="$work/rule9-$(basename "$staged" .yml.shadow-staged)"
  mkdir -p "$dir/.github/workflows"
  cp "$staged" "$dir/.github/workflows/$target_name"
  set +e; out="$(cd "$dir" && env -u GITHUB_REPOSITORY python3 "$lint_py" 2>&1)"; rc=$?; set -e
  errs="$(printf '%s\n' "$out" | grep -c '^::error::' || true)"
  # Scoped to rule=rule9, not a bare WAS-SHADOW count: a future shadow rule firing on the same
  # fixture must not be counted as rule9's own notice.
  notices="$(printf '%s\n' "$out" | grep -c '^::notice::WAS-SHADOW rule=rule9' || true)"
  if [ "$rc" -ne 0 ] || [ "$errs" -ne 0 ] || [ "$notices" -ne 1 ]; then
    echo "FAIL $name: expected exit 0 / 0 errors / 1 rule9 shadow notice, got exit=$rc errors=$errs notices=$notices"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  elif ! printf '%s\n' "$out" | grep -qF "$marker"; then
    echo "FAIL $name: expected the rule9 shadow notice to name the offending trigger(s) '$marker'"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  else
    echo "PASS $name (exit 0, 0 errors, rule9 shadow notice fired: '$marker')"
  fi
done

# rule9's FALSE-POSITIVE control, asserted explicitly rather than left to the sibling's good-*.yml
# loop: that loop only counts ::error::, which a SHADOW rule never emits, so it would happily pass
# this fixture even if rule9 fired on every workflow in the fleet. The ABSENCE of the notice is the
# test, and it is the assertion that makes the rule safe to run fleet-wide.
good9="$FIXTURES/good-rule9-default-types.yml"
if [ ! -f "$good9" ]; then
  echo "FAIL rule9 false-positive control: fixture $good9 not found"
  fail=1
else
  dir="$work/rule9-good-default-types"
  mkdir -p "$dir/.github/workflows"
  cp "$good9" "$dir/.github/workflows/"
  set +e; out="$(cd "$dir" && env -u GITHUB_REPOSITORY python3 "$lint_py" 2>&1)"; rc=$?; set -e
  notices="$(printf '%s\n' "$out" | grep -c '^::notice::WAS-SHADOW rule=rule9' || true)"
  if [ "$rc" -ne 0 ] || [ "$notices" -ne 0 ]; then
    echo "FAIL good-rule9-default-types.yml: the DEFAULT pull_request types plus an expression-valued"
    echo "     cancel-in-progress must NOT fire rule9 (got exit=$rc rule9-notices=$notices) — firing"
    echo "     here means the rule flags the default trigger shape, i.e. most of the fleet."
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  else
    echo "PASS good-rule9-default-types.yml (exit 0, rule9 correctly silent on the default types)"
  fi
fi

# --- WAS joint #3 Layer 3-2: canary-enforce simulated-repo-identity proof ---
# Proves the canary-enforce routing end-to-end WITHOUT promoting any real rule: patch a SCRATCH COPY
# of the extracted lint so rule7 (still real "shadow" in checks.yml — untouched) is temporarily
# {"mode": "canary-enforce", "repos": ["canary-repo"]}, then run the already-staged
# bad-rule7-no-timeout fixture under simulated GITHUB_REPOSITORY values:
#   - the named canary repo            -> must ENFORCE (::error::, exit 1)
#   - a different repo                 -> must only SHADOW (::notice::WAS-SHADOW, exit 0)
#   - GITHUB_REPOSITORY unset (local)  -> must only SHADOW (unknown-repo safety default)
# Promoting rule7 (or any rule) to a REAL canary-enforce is a separate, governed step
# (scripts/promote-rule.sh + a ledger grant) — this test only proves the mechanism.
canary_fixture="$FIXTURES/bad-rule7-no-timeout.yml.shadow-staged"
if [ ! -f "$canary_fixture" ]; then
  echo "FAIL canary-enforce proof: fixture $canary_fixture not found"
  fail=1
else
  canary_lint="$work/workflow-policy-lint.canary-test.py"
  patch_out="$(python3 - "$lint_py" "$canary_lint" <<'PATCH'
import re, sys
src_path, out_path = sys.argv[1], sys.argv[2]
src = open(src_path).read()
patched, n = re.subn(r'"rule7"\s*:\s*"shadow"',
                      '"rule7": {"mode": "canary-enforce", "repos": ["canary-repo"]}',
                      src, count=1)
if n != 1:
    sys.exit('canary-test setup: could not find a lone "rule7": "shadow" entry to patch (SEVERITY drift?)')
open(out_path, "w").write(patched)
print("patched")
PATCH
)" && patch_rc=0 || patch_rc=$?
  if [ "$patch_rc" -ne 0 ] || [ ! -s "$canary_lint" ]; then
    echo "FAIL canary-enforce proof: could not patch a test-only rule7 canary-enforce entry: $patch_out"
    fail=1
  else
    run_canary() {
      # $1 = GITHUB_REPOSITORY value to simulate (empty string = leave unset)
      local repo_env="$1" dir
      dir="$work/canary-run-$(echo "${repo_env:-unset}" | tr '/' '_')"
      mkdir -p "$dir/.github/workflows"
      cp "$canary_fixture" "$dir/.github/workflows/bad-rule7-no-timeout.yml"
      if [ -n "$repo_env" ]; then
        ( cd "$dir" && GITHUB_REPOSITORY="$repo_env" python3 "$canary_lint" )
      else
        ( cd "$dir" && env -u GITHUB_REPOSITORY python3 "$canary_lint" )
      fi
    }

    set +e; out="$(run_canary "wave-av/canary-repo" 2>&1)"; rc=$?; set -e
    errs="$(printf '%s\n' "$out" | grep -c '^::error::' || true)"
    if [ "$rc" -eq 1 ] && [ "$errs" -eq 1 ]; then
      echo "PASS canary-enforce: GITHUB_REPOSITORY=wave-av/canary-repo -> ENFORCE (exit1, 1 ::error::)"
    else
      echo "FAIL canary-enforce: named canary repo expected exit1/1 error, got exit=$rc errors=$errs"
      printf '%s\n' "$out" | sed 's/^/    /'
      fail=1
    fi

    set +e; out="$(run_canary "wave-av/other-repo" 2>&1)"; rc=$?; set -e
    # Scoped to rule=rule7 specifically (not a bare WAS-SHADOW count): the bad-rule7 fixture also
    # exercises push+pull_request, so an unrelated shadow rule (e.g. rule8) firing on the SAME
    # fixture must not be mistaken for rule7's own routed notice.
    notices="$(printf '%s\n' "$out" | grep -c '^::notice::WAS-SHADOW rule=rule7' || true)"
    if [ "$rc" -eq 0 ] && [ "$notices" -eq 1 ]; then
      echo "PASS canary-enforce: GITHUB_REPOSITORY=wave-av/other-repo -> SHADOW (exit0, 1 ::notice::WAS-SHADOW)"
    else
      echo "FAIL canary-enforce: non-canary repo expected exit0/1 shadow notice, got exit=$rc notices=$notices"
      printf '%s\n' "$out" | sed 's/^/    /'
      fail=1
    fi

    set +e; out="$(run_canary "" 2>&1)"; rc=$?; set -e
    notices="$(printf '%s\n' "$out" | grep -c '^::notice::WAS-SHADOW rule=rule7' || true)"
    if [ "$rc" -eq 0 ] && [ "$notices" -eq 1 ]; then
      echo "PASS canary-enforce: GITHUB_REPOSITORY unset -> SHADOW (unknown-repo safety default)"
    else
      echo "FAIL canary-enforce: unset GITHUB_REPOSITORY expected exit0/1 shadow notice (safety default), got exit=$rc notices=$notices"
      printf '%s\n' "$out" | sed 's/^/    /'
      fail=1
    fi
  fi
fi

if [ "$fail" = 0 ]; then
  echo "✓ workflow-policy SHADOW self-test: rule8 + rule9 shadow fixtures, rule9's false-positive control, and canary-enforce routing all behave as expected against the DEPLOYED lint in $CHECKS_YML"
else
  echo "✗ workflow-policy SHADOW self-test FAILED — rule8's or rule9's shadow fixtures, rule9's false-positive control, or canary-enforce routing regressed" >&2
fi
exit "$fail"
