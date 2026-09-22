#!/usr/bin/env bash
# test-public-repo-guard-content-policy.sh — drills the three "unresolvable reference"
# rules in scripts/public-repo-guard/content-policy.sh against real fixtures.
#
# WHY THIS EXISTS. A public repo cannot resolve anything that lives in a repo in the
# same org that is not published. There are three distinct shapes of that bug, they
# fail at three different moments, and only one of them was guarded:
#
#   1. `uses:` a reusable workflow  → run fails before any job is created (CI-visible)
#   2. a composite-action path      → job fails at the step (CI-visible)
#   3. a raw.githubusercontent.com  → NOTHING fails in CI. The tree is valid, every
#      fetch at run time            gate is green, and the 404 lands later in a
#                                   consumer's environment.
#
# Shape 3 is the reason this file is a test and not a code review: a rule whose whole
# job is to catch the failure CI cannot see has to be proven by execution, because
# there is no build that will ever go red if the regex is subtly wrong.
#
# WHAT EACH CASE PINS is stated inline. Two are regression pins rather than coverage:
#
#   * Cases P3 and P1b (a bare comment, no `uses:` token) pin the blind spot that
#     produced a published undercount: a commented-out reference is still the payload.
#     It teaches a reader to write the broken thing, and one copy-paste into a workflow
#     ships the failure. Anchoring on `uses:` would have scored this tree clean while
#     such lines sat in it — which is exactly what happened twice. The composite-action
#     rule was never `uses:`-anchored; the reusable-workflow rule shipped that way, read
#     0 matches, and was re-anchored on the org-scoped PATH once a prose mention of the
#     identical path turned up in .github/workflows/pr-agent.yml. "Clean by the rule"
#     and "clean of the shape" are different claims; only the second is worth making.
#   * Cases N1/N2/N7 pin the `(?!-public/)` lookahead — the exemption for this repo's
#     own published sibling, on all three rules. Without a negative control, "the rule
#     fires" and "the rule fires on everything" look identical from a passing test.
#   * Cases N4/N5/N9 are the controls on the path-anchoring widening specifically. Going
#     from `uses:`-keyed to path-keyed is precisely where a false positive would appear,
#     so ordinary github.com hyperlinks — an issue link, an example PR URL, a blob link
#     to a workflow file — must all stay clean. They resolve for anyone with access and
#     execute nothing; only a `uses:`-resolvable path is the unresolvable artifact.
#
# Every fixture is assembled from variables at run time, so this tracked file contains
# no line that the rules under test would themselves match — a test for a leak gate
# must not be a leak, and must not need its own allowlist entry to survive the gate.
# The repo name used throughout ("acme-internal") is fictional.
#
# Each case runs the REAL script against a throwaway mktemp directory. Nothing is
# written into this repository.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
POLICY="$ROOT/scripts/public-repo-guard/content-policy.sh"

[ -f "$POLICY" ] || {
  echo "error: content-policy.sh not found at $POLICY" >&2
  exit 2
}
command -v rg >/dev/null 2>&1 || {
  echo "error: ripgrep (rg) required — the script under test refuses to run without it" >&2
  exit 2
}

# Fixture vocabulary. Assembled, never written literally (see header).
ORG='wave-av'
PRIV='acme-internal'        # stand-in for any repo in the org that is not published
PUB='acme-internal-public'  # the resolvable published sibling
RAWHOST='raw.githubusercontent.com'
GH='github.com'

PASS=0
FAIL=0
GUARD_OUT=''
GUARD_RC=0

# run_guard <filename> <content> — scan a one-file tree with the real gate.
run_guard() {
  local name="$1" content="$2" dir
  dir="$(mktemp -d)" || { echo "error: mktemp failed" >&2; exit 2; }
  printf '%s\n' "$content" >"$dir/$name"
  GUARD_OUT="$(bash "$POLICY" "$dir" 2>&1)"
  GUARD_RC=$?
  rm -rf "$dir"
}

# expect_block <case-id> <rule-name> <what-it-proves> <filename> <content>
expect_block() {
  local id="$1" rule="$2" proves="$3" name="$4" content="$5"
  run_guard "$name" "$content"
  if (( GUARD_RC == 1 )) && printf '%s' "$GUARD_OUT" | grep -q "public-repo-guard ($rule)"; then
    echo "  ok   $id — $proves"
    PASS=$((PASS + 1))
  else
    echo "  FAIL $id — $proves"
    echo "       expected: exit 1 with rule '$rule'; got exit $GUARD_RC"
    printf '       %s\n' "$GUARD_OUT"
    FAIL=$((FAIL + 1))
  fi
}

# expect_clean <case-id> <what-it-proves> <filename> <content>
expect_clean() {
  local id="$1" proves="$2" name="$3" content="$4"
  run_guard "$name" "$content"
  if (( GUARD_RC == 0 )) && printf '%s' "$GUARD_OUT" | grep -q 'content policy OK'; then
    echo "  ok   $id — $proves"
    PASS=$((PASS + 1))
  else
    echo "  FAIL $id — $proves"
    echo "       expected: exit 0 and a clean report; got exit $GUARD_RC"
    printf '       %s\n' "$GUARD_OUT"
    FAIL=$((FAIL + 1))
  fi
}

echo "test-public-repo-guard-content-policy: unresolvable-reference rules"
echo
echo "positives — the gate must BLOCK:"

expect_block P1 unresolvable-uses \
  'shape 1: uses: a reusable workflow in an unpublished org repo (pins the shipped rule against regression)' \
  'workflow.yml' \
  "jobs:
  gate:
    uses: $ORG/$PRIV/.github/workflows/reusable-chassis-gate.yml@main"

expect_block P1b unresolvable-uses \
  'shape 1 inside a COMMENT with no uses: token — the direct analogue of P3; a uses:-anchored rule scored a tree clean while this exact line sat in .github/workflows/pr-agent.yml' \
  'pr-agent.yml' \
  "# GitHub does not let a PUBLIC repo call a reusable workflow from a PRIVATE one, so
# \`$ORG/$PRIV/.github/workflows/reusable-pr-agent.yml@main\` never resolves."

expect_block P1c unresolvable-uses \
  'shape 1 with the target quoted — the case the old optional-quote character class existed for, now covered by construction' \
  'workflow.yml' \
  "    uses: \"$ORG/$PRIV/.github/workflows/reusable-chassis-gate.yml@main\""

expect_block P2 unresolvable-action \
  'shape 2: uses: a composite action in an unpublished org repo' \
  'workflow.yml' \
  "      - uses: $ORG/$PRIV/.github/actions/chassis-check@main"

expect_block P3 unresolvable-action \
  'shape 2 inside a COMMENT with no uses: token — the undercount blind spot; a commented reference is still the payload' \
  'zizmor.yml' \
  "  unpinned-uses:
    # references the composite action $ORG/$PRIV/.github/actions/funnel-check by @main.
    ignore:
      - reusable-funnel-gate.yml"

expect_block P4 unresolvable-raw-fetch \
  'shape 3: a runtime fetch from an unpublished org repo in a shell variable — the failure CI never sees' \
  'ground-agent.sh' \
  "STATE_URL_DEFAULT=\"https://$RAWHOST/$ORG/$PRIV/v1/frameworks/platform-registry/state.json\""

expect_block P5 unresolvable-raw-fetch \
  'shape 3 in a .md code fence (curl | bash) — proves the rule has no file-extension filter, so docs and templates are covered' \
  'claude-session-start.md' \
  '```json
{
  "hooks": {
    "SessionStart": [
      { "command": "bash -c '"'"'curl -sSfL https://'"$RAWHOST"'/'"$ORG"'/'"$PRIV"'/v1/scripts/ground-agent.sh | bash'"'"'" }
    ]
  }
}
```'

expect_block P6 unresolvable-raw-fetch \
  'shape 3 in a TypeScript string literal — proves the rule is syntax-agnostic, not YAML/shell-shaped' \
  'check-drift.ts' \
  "    const url = 'https://$RAWHOST/$ORG/$PRIV/v1/frameworks/platform-registry/state.json';"

echo
echo "negatives — false-positive controls, the gate must stay CLEAN:"

expect_clean N1 \
  'the published -public sibling is exempt for composite actions (pins the (?!-public/) lookahead)' \
  'workflow.yml' \
  "      - uses: $ORG/$PUB/.github/actions/chassis-check@main"

expect_clean N2 \
  'the published -public sibling is exempt for raw fetches (same lookahead, second rule)' \
  'fetch.sh' \
  "STATE_URL=\"https://$RAWHOST/$ORG/$PUB/v1/frameworks/platform-registry/state.json\""

expect_clean N3 \
  'a same-repo local action path has no owner/repo prefix and must never match — it is the working fleet pattern' \
  'workflow.yml' \
  '      - uses: ./.github/actions/chassis-check'

expect_clean N4 \
  'a plain issue hyperlink into an unpublished org repo is not a reference and must not be flagged — the control that matters most now all three rules are path-anchored rather than uses:-anchored' \
  'README.md' \
  "- [roadmap](https://$GH/$ORG/$PRIV/issues/95) — O-series products"

expect_clean N5 \
  'the example PR URL form used by the changelog gate test must not be flagged (real line in this tree); second control on the path-anchoring widening' \
  'test-changelog-unreleased.sh' \
  "    echo \"https://$GH/$ORG/$PRIV/pull/\${NEW_PR:-9001}\""

expect_clean N7 \
  'the published -public sibling is exempt for reusable workflows too (pins the lookahead on the re-anchored shape 1 rule)' \
  'workflow.yml' \
  "    uses: $ORG/$PUB/.github/workflows/reusable-chassis-gate.yml@main"

expect_clean N8 \
  'a same-repo local reusable-workflow path carries no owner/repo prefix and must never match' \
  'workflow.yml' \
  '    uses: ./.github/workflows/reusable-chassis-gate.yml'

expect_clean N9 \
  'a browser hyperlink to a workflow FILE in an unpublished org repo must not be flagged — it resolves for anyone with access and executes nothing; the blob/<ref>/ segment is what keeps it out' \
  'README.md' \
  "See [the reusable lane](https://$GH/$ORG/$PRIV/blob/main/.github/workflows/reusable-pr-agent.yml)."

expect_clean N6 \
  'the documented # guard:allow <reason> escape hatch still suppresses these rules, like every other rule' \
  'workflow.yml' \
  "      - uses: $ORG/$PRIV/.github/actions/chassis-check@main  # guard:allow fixture in a gate drill"

echo
TOTAL=$((PASS + FAIL))
if (( FAIL > 0 )); then
  echo "test-public-repo-guard-content-policy: $PASS/$TOTAL passed, $FAIL FAILED"
  exit 1
fi
echo "test-public-repo-guard-content-policy: $PASS/$TOTAL passed"
