#!/usr/bin/env bash
# advance-major-tag.sh — SAFELY advance a moving major tag (v1, v2, …) for wave-foundation.
#
# Consumers pin the moving major tag (`uses: .../checks.yml@v1`) so they pick up non-breaking vN.x
# updates automatically. That convenience is also a footgun: a bare `git tag -f v1 <ref> && git push -f`
# points the ENTIRE FLEET at <ref> with no checks. This session nearly pointed v1 at a release that
# PRE-DATED the gate-precision fix — which would have re-activated a known false-positive gate for every
# spoke at once.
#
# This wrapper makes the advance safe:
#   1) the target is the NEWEST full vN.Y.Z release tag for the major (never an arbitrary/stale commit);
#   2) the gate framework SELF-TESTS pass at that exact tree (registry↔pre-commit parity, the
#      request-shape linter correctly flags a known-bad snippet AND passes a known-good one, and
#      the WAS workflow-policy lint inlined in checks.yml still correctly flags each of rules 1-5);
#   3) only then is `vN` force-updated and force-pushed.
#
# Usage:
#   scripts/advance-major-tag.sh v1            # advance v1 -> newest v1.Y.Z (after self-tests)
#   scripts/advance-major-tag.sh v1 --dry-run  # verify only; never tag or push
set -euo pipefail

MAJOR="${1:-}"
DRY=0
[ "${2:-}" = "--dry-run" ] && DRY=1

die() { echo "error: $*" >&2; exit 1; }

[[ "$MAJOR" =~ ^v[0-9]+$ ]] || die "usage: advance-major-tag.sh vN [--dry-run] (got: '${MAJOR:-}')"
command -v git >/dev/null 2>&1 || die "git not installed"
[ -d frameworks/gates ] || die "run from the repo root (frameworks/gates not found)"

git fetch --quiet --tags --force origin || die "git fetch failed"

# 1) newest full vN.Y.Z release tag for this major (semver sort; never the moving tag itself).
target="$(git tag -l "${MAJOR}.*.*" --sort=-v:refname | grep -E "^${MAJOR}\.[0-9]+\.[0-9]+$" | head -1 || true)"
[ -n "$target" ] || die "no full ${MAJOR}.Y.Z release tag exists yet — cut a release first (scripts/release.sh)"
target_sha="$(git rev-parse "$target^{commit}")"
echo "→ ${MAJOR} would advance to ${target} (${target_sha:0:9})"

# 1b) MONOTONICITY. The self-tests below validate the TARGET, and they pass at any healthy release —
#     including one that is BEHIND where ${MAJOR} already points. Nothing here compared the two, so a
#     green self-test run was sufficient to force-push the fleet's gate BACKWARD while printing a
#     success line. Measured 2026-07-30: v1 was at 8ff3037e and the newest release tag v1.14.0 was
#     24 commits behind it (106 behind main); all 15 self-tests passed at v1.14.0, so this script
#     would have rewound every consumer's gate by 24 commits and called it an advance.
#
#     "Advance" has to mean advance. Absence of a comparison is not a comparison.
current_sha="$(git rev-parse --verify --quiet "refs/tags/${MAJOR}^{commit}" 2>/dev/null || true)"
if [ -z "$current_sha" ]; then
  echo "→ ${MAJOR} does not exist yet — first advance, nothing to rewind."
elif [ "$current_sha" = "$target_sha" ]; then
  # Idempotent, not an error: re-running after a successful advance must be a safe no-op.
  echo "✓ ${MAJOR} already points at ${target} (${target_sha:0:9}) — nothing to do."
  exit 0
elif ! git merge-base --is-ancestor "$current_sha" "$target_sha"; then
  behind="$(git rev-list --count "${target_sha}..${current_sha}" 2>/dev/null || echo '?')"
  if [ "${WAVE_ALLOW_TAG_REWIND:-0}" = "1" ]; then
    # A deliberate emergency rollback is a real use case and must not require editing this script.
    # It must, however, be impossible to do by accident.
    echo "::warning::WAVE_ALLOW_TAG_REWIND=1 — moving ${MAJOR} BACKWARD by ${behind} commit(s) on purpose."
  else
    die "REFUSING to move ${MAJOR} backward.
  ${MAJOR} currently points at ${current_sha:0:9}, which is NOT an ancestor of ${target} (${target_sha:0:9}).
  That would rewind the shared gate by ${behind} commit(s) for every repo consuming '@${MAJOR}'.
  The newest release tag is older than the tag itself — cut a release at current main first
  (scripts/release.sh vX.Y.Z), then re-run this.
  Deliberate rollback: WAVE_ALLOW_TAG_REWIND=1 (say so out loud in the PR/incident)."
  fi
fi

# 2) gate self-tests AT THAT TREE. Extract the tag's tree to a scratch dir (no worktree → dodges the
#    concurrent-prune hazard on a contended clone) and run the framework's own checks there.
scratch="$(mktemp -d)"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT
git archive "$target" | tar -x -C "$scratch"

echo "→ self-test: gate registry ↔ pre-commit parity (emit.py --check)"
( cd "$scratch" && python3 frameworks/gates/emit.py --check ) \
  || die "gate registry/pre-commit drift at ${target} — DO NOT activate this ref fleet-wide"

LINT="$scratch/frameworks/claude-api/lint-request-shape.sh"
if [ -f "$LINT" ]; then
  echo "→ self-test: request-shape linter flags a known-bad shape and passes a known-good one"
  bad="$scratch/.selftest-bad.py"; good="$scratch/.selftest-good.py"
  # known-BAD: temperature on an Opus-4.x request (the Opus-400 bug class this gate exists for)  claude-api-lint: ignore
  printf 'client.messages.create(model="claude-opus-4-8", temperature=0.7, max_tokens=10)\n' > "$bad"  # claude-api-lint: ignore (intentional bad fixture)
  # known-GOOD: the correct adaptive-thinking shape
  printf 'client.messages.create(model="claude-opus-4-8", thinking={"type":"adaptive"}, max_tokens=10)\n' > "$good"
  if bash "$LINT" "$bad" >/dev/null 2>&1; then
    die "request-shape linter at ${target} did NOT flag a known-bad sampling-param shape on Opus-4.x — the gate is broken; refusing to activate it fleet-wide"  # claude-api-lint: ignore
  fi
  bash "$LINT" "$good" >/dev/null 2>&1 \
    || die "request-shape linter at ${target} FALSE-POSITIVES on a known-good shape — refusing to activate (this is exactly the regression we are guarding against)"
  echo "  ✓ linter correctly flags bad / passes good"
else
  echo "::notice::no request-shape linter at ${target} (frameworks/claude-api not present yet) — skipping that self-test"
fi

WAS_TEST="$scratch/frameworks/gates/test-workflow-policy.sh"
if [ -f "$WAS_TEST" ]; then
  echo "→ self-test: WAS workflow-policy rules 1-5 (sourced live from checks.yml) against golden fixtures"
  ( cd "$scratch" && bash frameworks/gates/test-workflow-policy.sh ) \
    || die "WAS workflow-policy self-test FAILED at ${target} — a workflow-policy rule (1-5) regressed; refusing to activate it fleet-wide"
  echo "  ✓ WAS rules 1-5 each correctly flag their known-bad fixture and pass known-good ones"
else
  echo "::notice::no frameworks/gates/test-workflow-policy.sh at ${target} — skipping that self-test"
fi

echo "✓ all gate self-tests pass at ${target}"

if [ "$DRY" = 1 ]; then
  echo "--dry-run: would 'git tag -f ${MAJOR} ${target} && git push -f origin ${MAJOR}'. Not doing it."
  exit 0
fi

# 3) advance + force-push the moving tag.
git tag -f "$MAJOR" "$target"
git push -f origin "$MAJOR"
echo "✓ ${MAJOR} now points at ${target} (${target_sha:0:9}); consumers on @${MAJOR} pick it up."
