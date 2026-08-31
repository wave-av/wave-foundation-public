#!/usr/bin/env bash
# Drill for scripts/advance-major-tag.sh — the monotonicity guard (1b) and the
# behaviour-arming guard (1c).
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

# Like make_repo, but every commit carries SIX callable-surface fixtures:
#   checks.yml                        (workflow_call)     default flips false->true at commit $3
#   reusable-other.yml                (workflow_call)     default flips false->true at commit $4 (99 = never)
#   dispatch-only.yml                 (workflow_dispatch) default flips false->true at commit $5 (99 = never)
#   .github/actions/demo/action.yml   (composite action)  default flips false->true at commit $6 (99 = never)
#   dual-trigger.yml                  (workflow_call AND workflow_dispatch in one `on:` block)
#                                     dispatch default flips at $7, call default flips at $8
#   flow-style.yml                    (workflow_call, FLOW-style input map on one line)
#                                     default flips at $9 (99 = never)
# The guard (1c) must arm on EITHER reusable's flip AND on the composite action's (both are
# consumable at @vN), and must IGNORE the dispatch-only one: a manual trigger's default arms no
# @vN consumer. The dual-trigger file pins the subtree scoping: only its workflow_call defaults
# count, even though its workflow_dispatch inputs sit inside the same `on:` block. The flow-style
# file pins parser-based extraction: its whole input map sits on ONE line, the spelling the old
# line-based extractor could not see at all (bench.yml is written exactly this way).
make_repo_gate() { # $1=v1_at $2=release_at $3=checks_flip $4=other_flip $5=dispatch_flip $6=action_flip $7=dual_dispatch_flip $8=dual_call_flip $9=flow_flip
  local v1_at="$1" rel_at="$2" flip_at="$3" other_at="${4:-99}" disp_at="${5:-99}" act_at="${6:-99}" duald_at="${7:-99}" dualc_at="${8:-99}" flow_at="${9:-99}"
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/amt.XXXXXX")"
  git init -q -b main "$d/repo"
  git -C "$d/repo" config user.email drill@wave.online
  git -C "$d/repo" config user.name drill
  mkdir -p "$d/repo/frameworks/gates" "$d/repo/scripts" "$d/repo/.github/workflows" "$d/repo/.github/actions/demo"
  local i dflt
  for i in $(seq 1 10); do
    echo "$i" > "$d/repo/frameworks/gates/.keep"
    dflt=false; [ "$i" -ge "$flip_at" ] && dflt=true
    printf 'on:\n  workflow_call:\n    inputs:\n      enforce_claude_config:\n        type: boolean\n        default: %s\npermissions:\n  contents: read\n' "$dflt" \
      > "$d/repo/.github/workflows/checks.yml"
    dflt=false; [ "$i" -ge "$other_at" ] && dflt=true
    printf 'on:\n  workflow_call:\n    inputs:\n      enforce_other_gate:\n        type: boolean\n        default: %s\npermissions:\n  contents: read\n' "$dflt" \
      > "$d/repo/.github/workflows/reusable-other.yml"
    dflt=false; [ "$i" -ge "$disp_at" ] && dflt=true
    printf 'on:\n  workflow_dispatch:\n    inputs:\n      verbose:\n        type: boolean\n        default: %s\npermissions:\n  contents: read\n' "$dflt" \
      > "$d/repo/.github/workflows/dispatch-only.yml"
    dflt=false; [ "$i" -ge "$act_at" ] && dflt=true
    printf 'name: demo\ninputs:\n  strict:\n    default: %s\nruns:\n  using: composite\n  steps: []\n' "$dflt" \
      > "$d/repo/.github/actions/demo/action.yml"
    local dualc=false duald=false
    [ "$i" -ge "$dualc_at" ] && dualc=true
    [ "$i" -ge "$duald_at" ] && duald=true
    printf 'on:\n  workflow_call:\n    inputs:\n      enforce_dual_gate:\n        type: boolean\n        default: %s\n  workflow_dispatch:\n    inputs:\n      verbose:\n        type: boolean\n        default: %s\npermissions:\n  contents: read\n' "$dualc" "$duald" \
      > "$d/repo/.github/workflows/dual-trigger.yml"
    dflt=false; [ "$i" -ge "$flow_at" ] && dflt=true
    printf 'on:\n  workflow_call:\n    inputs:\n      min_grade: { description: "floor", required: false, type: boolean, default: %s }\npermissions:\n  contents: read\n' "$dflt" \
      > "$d/repo/.github/workflows/flow-style.yml"
    git -C "$d/repo" add -A
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
# Set AMT_ARGS to pass extra positional args (e.g. --dry-run) to the script under test.
check() {
  local label="$1" d="$2" want_rc="$3" want="$4" nowant="${5:-}"; shift 5 2>/dev/null || shift 4
  local out rc
  out="$(cd "$d/repo" && env "$@" bash scripts/advance-major-tag.sh v1 ${AMT_ARGS:-} 2>&1)"
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
echo "== advance-major-tag: behaviour-arming guard =="

# A forward advance whose target CHANGES the gate's input defaults is a fleet-wide arming event
# (CONSUME.md §3) and must be refused until acknowledged out loud.
check "defaults changed -> arming REFUSED" \
  "$(make_repo_gate 3 8 6)" 1 "changes gate input defaults" "now points at"

check "WAVE_ACK_GATE_ARMING=1 permits the arming" \
  "$(make_repo_gate 3 8 6)" any "arming acknowledged" "REFUSING" \
  WAVE_ACK_GATE_ARMING=1

# checks.yml is not the only arming surface: a default flip in ANY workflow_call reusable is the
# same fleet-wide event and must be refused too (the guard names the file that changed).
check "defaults changed in ANOTHER reusable -> arming REFUSED" \
  "$(make_repo_gate 3 8 99 6)" 1 "reusable-other.yml input DEFAULTS" "now points at"

# A composite action's inputs are consumable at @vN too (OPEN-CORE.md publishes chassis-check
# precisely so public callers can reach it), so its default flip is the same arming event.
check "defaults changed in a composite ACTION -> arming REFUSED" \
  "$(make_repo_gate 3 8 99 99 99 6)" 1 "actions/demo/action.yml input DEFAULTS" "now points at"

# Routine releases that do not touch gate defaults must advance unprompted.
check "defaults unchanged -> no arming prompt" \
  "$(make_repo_gate 6 8 2)" any "v1 would advance to v1.9.0" "REFUSING"

# A workflow_dispatch-only default is a manual trigger's default: it arms no @vN consumer, so a
# flip there must NOT prompt (over-arming would train releasers to ack reflexively).
check "dispatch-only default flip -> no arming prompt" \
  "$(make_repo_gate 6 8 2 99 7)" any "v1 would advance to v1.9.0" "REFUSING"

# THE OVER-MATCH THIS PINS (Devin, PR #1163): a reusable that ALSO has workflow_dispatch. The old
# extraction read the whole `on:` block, so a dispatch default flipping inside a workflow_call
# file prompted an arming ack for an event no @vN consumer can see. Only the workflow_call
# subtree may count.
check "dual-trigger: dispatch flip only -> no arming prompt" \
  "$(make_repo_gate 6 8 2 99 99 99 7)" any "v1 would advance to v1.9.0" "REFUSING"

# ...and the same file's workflow_call default flipping IS the arming event, dispatch noise or not.
check "dual-trigger: CALL default flip -> arming REFUSED" \
  "$(make_repo_gate 3 8 99 99 99 99 99 6)" 1 "dual-trigger.yml input DEFAULTS" "now points at"

# THE BLIND SPOT THIS PINS (Devin, PR #1163): a FLOW-style input map, the whole spec on one
# line, exactly how bench.yml declares min_grade. The old line-based extractor emitted zero
# pairs for that spelling at both commits, compared equal, and the flip armed the fleet with
# no prompt. The parser-based extractor must refuse it like any other workflow_call flip.
check "flow-style CALL default flip -> arming REFUSED" \
  "$(make_repo_gate 3 8 99 99 99 99 99 99 6)" 1 "flow-style.yml input DEFAULTS" "now points at"

# --dry-run exists to verify a target: it must report the would-be refusal and still reach the
# self-tests instead of aborting at the guard.
AMT_ARGS="--dry-run"
check "--dry-run reports the arming but continues" \
  "$(make_repo_gate 3 8 6)" any "a real advance would REFUSE here" "REFUSING to advance"
unset AMT_ARGS

echo
if [ "$fail" -eq 0 ]; then
  echo "advance-major-tag self-test: ${pass} case(s) passed"
  exit 0
fi
echo "advance-major-tag self-test: ${fail} case(s) FAILED (${pass} passed)" >&2
exit 1
