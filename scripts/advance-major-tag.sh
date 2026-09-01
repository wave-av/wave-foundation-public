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

# 1c) BEHAVIOUR-ARMING SURFACE (CONSUME.md §3). Every release moves this tag (RELEASING.md), so
#     "review what behaviour changed before re-pointing vN" cannot live in a runbook footnote — it
#     has to be enforced HERE, on the only path that moves the tag. A dormant gate flipping its
#     default (e.g. enforce_claude_config false→true) arms the ENTIRE @vN fleet the moment this
#     script pushes; a releaser cutting an unrelated patch must not do that as an invisible side
#     effect. And checks.yml is not the only such surface: EVERY workflow_call reusable in
#     .github/workflows/ and every composite action under .github/actions/ is consumable at @vN
#     (OPEN-CORE.md publishes chassis-check precisely so public callers can reach it), so a
#     default flip in any of them is the same class of event. Compare each surface's *input
#     defaults* between where vN points now and the target: if any differ, the advance is an
#     arming event and requires explicit acknowledgment.
if [ -n "$current_sha" ]; then
  # ENUMERATE FIRST, CHECK THE STATUS, THEN COMPARE (#944): a listing that fails inside a process
  # substitution is indistinguishable from "no callable surfaces changed", and the tag would
  # force-push with the arming review silently skipped. An unverifiable arming review blocks.
  list_surfaces() { # $1=sha: every fleet-consumable defaults surface at that commit
    local out
    out="$(git ls-tree -r --name-only "$1" -- .github/workflows/ .github/actions/)" \
      || die "REFUSING to advance ${MAJOR}: cannot enumerate callable surfaces at ${1:0:9}. The arming review (1c) is unverifiable, and an unverifiable review must block the tag move, not pass it (#944)."
    printf '%s\n' "$out" | grep -E '^\.github/(workflows/[^/]+\.ya?ml|actions/.+/action\.ya?ml)$' | sort || true
  }
  # Both extractors emit sorted "input_name default: value" PAIRS, not raw `default:` lines:
  # name-paired so a change is attributable to one input, sorted so an unrelated input reorder
  # cannot read as an arming event. And the workflow extractor descends ONLY into the
  # `on: -> workflow_call:` subtree: a dual-trigger reusable also carries workflow_dispatch
  # inputs inside the same `on:` block, and a manual-run default arms nobody downstream, so
  # comparing the whole block would refuse releases for a change that affects no consumer.
  #
  # Extraction is a REAL YAML PARSE, not line-matching (Devin, PR #1163). The previous awk
  # extractors recognised a default only when `default:` started its own line, so a flow-style
  # input map (`min_grade: { ..., default: "B" }`, exactly how bench.yml is written) emitted
  # ZERO pairs at both commits, compared equal, and a flipped default in that published reusable
  # armed the fleet with no prompt. Block-scalar defaults (`default: |`) had the same blind spot.
  # A parser sees every YAML spelling; no parser means the review is unverifiable, which BLOCKS
  # (#944) rather than silently comparing empty strings.
  python3 -c 'import yaml' 2>/dev/null \
    || die "REFUSING to advance ${MAJOR}: the arming review (1c) needs python3 + PyYAML to read input defaults (pip3 install pyyaml). An unverifiable arming review must block the tag move, not pass it (#944)."
  extract_defaults() { # $1=call|action; stdin: YAML; sorted pairs on stdout; non-zero on a failed parse
    # The program rides in -c, NOT a heredoc: `python3 -` would consume stdin for the program
    # and silently starve yaml.safe_load of the piped document (empty pairs = a fail-open compare).
    python3 -c '
import sys, yaml
doc = yaml.safe_load(sys.stdin) or {}
if sys.argv[1] == "call":
    on = doc.get("on", doc.get(True)) or {}   # YAML 1.1 reads a bare on: key as boolean True
    wc = on.get("workflow_call") if isinstance(on, dict) else None
    inputs = (wc.get("inputs") or {}) if isinstance(wc, dict) else {}
else:
    inputs = doc.get("inputs") or {}
for name in sorted(inputs):
    spec = inputs[name]
    if isinstance(spec, dict) and "default" in spec:
        print(name, "default:", repr(spec["default"]))
' "$1"
  }
  call_defaults() { extract_defaults call; }
  action_defaults() { extract_defaults action; }
  cur_surfaces="$(list_surfaces "$current_sha")"
  tgt_surfaces="$(list_surfaces "$target_sha")"
  surfaces="$(comm -12 <(printf '%s\n' "$cur_surfaces") <(printf '%s\n' "$tgt_surfaces"))" \
    || die "REFUSING to advance ${MAJOR}: cannot intersect the surface listings. The arming review (1c) is unverifiable; refusing to fail open (#944)."
  armed=0
  # Only files present at BOTH commits can arm: a brand-new reusable has no @vN consumer yet
  # (adding a `uses:` line is the consumer's own deliberate act), and a deleted one fails its
  # callers loudly at parse time (a different, visible failure class). Only callable surfaces
  # count: a workflow_dispatch-only default arms nobody downstream, while a composite action's
  # `inputs:` are callable by construction.
  while IFS= read -r sf; do
    [ -n "$sf" ] || continue
    cur_c="$(git show "${current_sha}:${sf}")" \
      || die "REFUSING to advance ${MAJOR}: cannot read ${sf} at ${current_sha:0:9}. The arming review (1c) is unverifiable; refusing to fail open (#944)."
    tgt_c="$(git show "${target_sha}:${sf}")" \
      || die "REFUSING to advance ${MAJOR}: cannot read ${sf} at ${target_sha:0:9}. The arming review (1c) is unverifiable; refusing to fail open (#944)."
    case "$sf" in
      */action.yml|*/action.yaml)
        cur_defaults="$(printf '%s\n' "$cur_c" | action_defaults)" \
          || die "REFUSING to advance ${MAJOR}: cannot parse ${sf} at ${current_sha:0:9}. The arming review (1c) is unverifiable; refusing to fail open (#944)."
        tgt_defaults="$(printf '%s\n' "$tgt_c" | action_defaults)" \
          || die "REFUSING to advance ${MAJOR}: cannot parse ${sf} at ${target_sha:0:9}. The arming review (1c) is unverifiable; refusing to fail open (#944)."
        ;;
      *)
        # No pipe into `grep -q` here: an early-exiting -q raises EPIPE under pipefail and a
        # real reusable could read as "not callable". A plain substring test cannot fail open.
        case "$cur_c$tgt_c" in *workflow_call:*) ;; *) continue ;; esac
        cur_defaults="$(printf '%s\n' "$cur_c" | call_defaults)" \
          || die "REFUSING to advance ${MAJOR}: cannot parse ${sf} at ${current_sha:0:9}. The arming review (1c) is unverifiable; refusing to fail open (#944)."
        tgt_defaults="$(printf '%s\n' "$tgt_c" | call_defaults)" \
          || die "REFUSING to advance ${MAJOR}: cannot parse ${sf} at ${target_sha:0:9}. The arming review (1c) is unverifiable; refusing to fail open (#944)."
        ;;
    esac
    if [ "$cur_defaults" != "$tgt_defaults" ]; then
      armed=1
      echo "::warning::${MAJOR} → ${target} changes ${sf} input DEFAULTS — this advance is a fleet-wide ARMING event (CONSUME.md §3)."
      echo "  ${sf} defaults at current ${MAJOR} (${current_sha:0:9}):"
      printf '%s\n' "${cur_defaults:-  (none)}" | sed 's/^/    /'
      echo "  ${sf} defaults at ${target} (${target_sha:0:9}):"
      printf '%s\n' "${tgt_defaults:-  (none)}" | sed 's/^/    /'
      echo "  commits touching ${sf} in ${current_sha:0:9}..${target_sha:0:9}:"
      git log --oneline "${current_sha}..${target_sha}" -- "$sf" | sed 's/^/    /'
    fi
  done <<< "$surfaces"
  if [ "$armed" = 1 ]; then
    if [ "${WAVE_ACK_GATE_ARMING:-0}" != "1" ]; then
      # --dry-run exists to VERIFY a target, and behaviour-arming releases are exactly the ones
      # most worth verifying — so the guard reports instead of aborting, and the self-tests below
      # still run. Nothing is tagged or pushed on a dry run either way.
      if [ "$DRY" = 1 ]; then
        echo "--dry-run: a real advance would REFUSE here without WAVE_ACK_GATE_ARMING=1 (gate input defaults changed). Continuing to the self-tests."
      else
        die "REFUSING to advance ${MAJOR}: this move changes gate input defaults, arming behaviour for every '@${MAJOR}' consumer.
  Review the defaults diff above (CONSUME.md §3), then re-run with WAVE_ACK_GATE_ARMING=1 to
  acknowledge the arming out loud. An unrelated fix must never arm a dormant gate as a side effect."
      fi
    else
      echo "::warning::WAVE_ACK_GATE_ARMING=1 — arming acknowledged; proceeding."
    fi
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
