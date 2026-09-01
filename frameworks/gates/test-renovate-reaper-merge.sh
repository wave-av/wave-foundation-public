#!/usr/bin/env bash
# test-renovate-reaper-merge.sh — self-test for renovate-reaper.yml's merge block. (#1193.)
#
# THE BLOCK UNDER TEST IS EXTRACTED FROM THE WORKFLOW AT RUN TIME, never copied into this file.
# A copy keeps passing after someone edits the workflow, which is the exact failure class this
# PR exists to close: the reaper reported `reaped: N` for 1,159 consecutive runs while merging
# nothing, because its merge output was piped into `tail -1` and the pipeline's exit status was
# tail's. A test that drills a stale copy of the logic is the same green-for-nothing shape.
#
# WHY THIS BLOCK IS WORTH DRILLING AT ALL. It is a cron job holding an owner-wide App token that
# merges into every spoke repo in the org, and its merge path has never once executed in
# production — every candidate to date is rejected upstream by the author-trust gate. So there
# is no live receipt for any of this behaviour and there will not be one until the day it
# matters. These cases are the only evidence that exists.
#
# Usage:  bash frameworks/gates/test-renovate-reaper-merge.sh
# Exit:   0 = every case behaved as specified · 1 = at least one regressed.
#
# SC1090: the extracted block is generated into a temp dir at run time, so its path cannot be a
# constant. This directive must precede the FIRST COMMAND to apply file-wide.
# shellcheck disable=SC1090
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
WF="${1:-$REPO_ROOT/.github/workflows/renovate-reaper.yml}"

# MIRROR GUARD — this file publishes to the open-core mirror (frameworks/gates/test-*.sh is
# allowlisted) but its SUBJECT does not: renovate-reaper.yml is internal fleet automation and stays
# private. Published without this, the drill would run in the mirror against a file that is not there
# and go red forever — the "shipped a workflow with its feet still in the private repo" class that
# scripts/sync-public.sh's dependency check exists to catch. It caught this one at authoring time.
# The path is written out literally rather than through $WF because that checker matches a guard that
# NAMES the file it protects; a variable would be a guard it cannot verify.
[ -f "$REPO_ROOT/.github/workflows/renovate-reaper.yml" ] || [ -n "${1:-}" ] || {
  echo "::notice::renovate-reaper.yml is not present (private-only subject) — nothing to drill here"
  exit 0
}
# Beyond the mirror, a named subject that is missing is an ERROR, not a skip. The two cases are
# deliberately not folded together: absent-because-private is expected, and absent-because-someone-
# passed-a-bad-path is a broken invocation that must not read as a pass.
[ -f "$WF" ] || { echo "error: $WF not found" >&2; exit 1; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
show() { printf '       %s\n' "$(printf '%s' "$1" | head -3)"; }

# ── extract ──────────────────────────────────────────────────────────────────────────────────────
# From `merge_ok=0` to the line before `done < /tmp/cands.txt`. Extraction that silently yields
# nothing would make every case below vacuously pass, so a missing block is FATAL, not a skip.
extract() {
  awk '/^[[:space:]]*merge_ok=0$/{f=1} /^[[:space:]]*done < \/tmp\/cands\.txt$/{f=0} f' "$1" \
    | sed 's/^            //'
}
extract "$WF" > "$work/block.sh"
if ! grep -q 'merge_ok=1' "$work/block.sh"; then
  echo "::error::extraction found no merge block in $WF — the anchors moved, or the block was deleted." >&2
  echo "Refusing to report green on zero cases." >&2
  exit 1
fi

# ── stub gh ──────────────────────────────────────────────────────────────────────────────────────
# A real executable on PATH, not a shell function: the block calls `gh` as a command, and a
# function would not survive the subshell each case runs in.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "pr merge")
    if printf '%s\n' "$@" | grep -qx -- '--auto'; then
      case "$CASE" in
        auto_ok) echo "enabled auto-merge"; exit 0 ;;
        clean_then_ok|clean_then_fail)
          # Verbatim shape of GitHub's enablePullRequestAutoMerge refusal.
          echo "failed to run git: Pull request Pull request is in clean status" >&2; exit 1 ;;
        *) echo "$OTHER_ERR" >&2; exit 1 ;;
      esac
    else
      case "$CASE" in
        clean_then_ok)   echo "Merged pull request #7"; exit 0 ;;
        clean_then_fail) echo "GraphQL: Base branch was modified" >&2; exit 1 ;;
        *) echo "unexpected direct merge" >&2; exit 1 ;;
      esac
    fi ;;
  "pr view") [ -n "${VIEW_OUT:-}" ] && { printf '%s\n' "$VIEW_OUT"; exit 0; }; exit 1 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$work/bin/gh"; export PATH="$work/bin:$PATH"

# run <block> <CASE> [VIEW_OUT] [OTHER_ERR] -> "<n> <failed> <combined output>"
run() {
  local blk="$1"; export CASE="$2" VIEW_OUT="${3-}" OTHER_ERR="${4-boom}"
  # NOT `out=$(. "$blk")` — command substitution is a SUBSHELL, so the block's `n`/`failed`
  # increments would be discarded and every counter assertion would read 0 and look meaningful.
  # SC2034: `num` and `R` are read by the SOURCED block, which shellcheck cannot follow.
  # shellcheck disable=SC2034
  ( set +e; num=7; R=wave-av/spoke; n=0; failed=0
    . "$blk" > "$work/out.txt" 2>&1
    printf '%s %s %s' "$n" "$failed" "$(cat "$work/out.txt")" )
}
counters() { printf '%s' "$1" | cut -d' ' -f1,2; }
body()     { printf '%s' "$1" | cut -d' ' -f3-; }

B="$work/block.sh"

# ── 1. the happy path ────────────────────────────────────────────────────────────────────────────
r=$(run "$B" auto_ok)
[ "$(counters "$r")" = "1 0" ] && pass "auto-merge accepted -> counted, not failed" \
  || { fail "auto-merge accepted -> counted, not failed"; show "$r"; }

# ── 2. the CLEAN refusal (#1193, Cursor) ─────────────────────────────────────────────────────────
# `--auto` is a DEFERRED merge and GitHub refuses it when the PR is ALREADY immediately
# mergeable. This loop approves one line earlier, so CLEAN is the NORMAL state, not an edge
# case — unhandled, every successful reap turns the hourly job red.
r=$(run "$B" clean_then_ok)
[ "$(counters "$r")" = "1 0" ] && pass "CLEAN refusal -> falls back to a direct merge" \
  || { fail "CLEAN refusal -> falls back to a direct merge"; show "$r"; }
case "$(body "$r")" in *"Merged pull request #7"*)
  pass "CLEAN refusal -> reports the direct merge, not the refusal" ;;
  *) fail "CLEAN refusal -> reports the direct merge, not the refusal"; show "$r" ;; esac

# ── 3. CLEAN refusal whose fallback ALSO fails -> still loud ──────────────────────────────────────
r=$(run "$B" clean_then_fail)
[ "$(counters "$r")" = "0 1" ] && pass "CLEAN refusal + failed fallback -> counted as failed" \
  || { fail "CLEAN refusal + failed fallback -> counted as failed"; show "$r"; }
case "$(body "$r")" in *"::error::reaper could not merge"*)
  pass "CLEAN refusal + failed fallback -> emits ::error::" ;;
  *) fail "CLEAN refusal + failed fallback -> emits ::error::"; show "$r" ;; esac

# ── 4-5. no-ops are not failures ──────────────────────────────────────────────────────────────────
# A second vendor error string (auto-merge already enabled by an earlier tick) is deliberately
# NOT matched textually — an unverified string is a guess, and a wrong guess reds the job on a
# no-op. State is asked for instead.
r=$(run "$B" other "MERGED auto-off")
[ "$(counters "$r")" = "1 0" ] && pass "already MERGED -> no-op, not a merge-lane failure" \
  || { fail "already MERGED -> no-op, not a merge-lane failure"; show "$r"; }
r=$(run "$B" other "OPEN auto-on")
[ "$(counters "$r")" = "1 0" ] && pass "auto-merge already enabled -> no-op, not a failure" \
  || { fail "auto-merge already enabled -> no-op, not a failure"; show "$r"; }

# ── 6-7. everything else fails CLOSED ────────────────────────────────────────────────────────────
r=$(run "$B" other "OPEN auto-off")
[ "$(counters "$r")" = "0 1" ] && pass "open + no auto-merge -> loud failure" \
  || { fail "open + no auto-merge -> loud failure"; show "$r"; }
r=$(run "$B" other "")
[ "$(counters "$r")" = "0 1" ] && pass "state unreadable -> fails CLOSED, never silently counted" \
  || { fail "state unreadable -> fails CLOSED, never silently counted"; show "$r"; }

# ── 8. workflow-command escaping (#1193, qodo) ───────────────────────────────────────────────────
# `gh` output is UNTRUSTED input to the runner's logging CONTROL channel: `%`, CR and LF are its
# escape syntax, so an unescaped message can corrupt the annotation or be re-parsed as another
# workflow command.
r=$(run "$B" other "" 'boom 50% off')
case "$(body "$r")" in *'50%25 off'*) pass "percent in gh output -> escaped to %25" ;;
  *) fail "percent in gh output -> escaped to %25"; show "$r" ;; esac
case "$(body "$r")" in *'50% off'*) fail "raw % must not survive into the annotation"; show "$r" ;;
  *) pass "raw % must not survive into the annotation" ;; esac
r=$(run "$B" other "" "$(printf 'boom\rSECOND')")
case "$(body "$r")" in *$'\r'*) fail "raw CR must not survive into the annotation"; show "$r" ;;
  *) pass "raw CR must not survive into the annotation" ;; esac

# ── mutants: prove the cases above DISCRIMINATE, not merely pass ─────────────────────────────────
# Run every time, not once on the author's machine — a case that cannot fail is a decoration.
mutant() { # mutant <name> <sed-expr> <case> <view> <expected-counters>
  local name="$1" expr="$2" c="$3" v="$4" want="$5" m="$work/mutant.sh" got
  sed -E "$expr" "$B" > "$m"
  got=$(counters "$(run "$m" "$c" "$v")")
  if [ "$got" = "$want" ]; then fail "MUTANT $name is not caught — the case cannot discriminate"
  else pass "MUTANT $name is caught (counters $got, not $want)"; fi
}
mutant "no CLEAN fallback"  's/pull request is in clean status/__NEVER_MATCHES__/' clean_then_ok ''            "1 0"
mutant "no state re-read"   's/MERGED\*\|\*auto-on\)/__NEVER__)/'                  other         "OPEN auto-on" "1 0"
# The escaping mutant is asserted on the BODY, so it gets its own arm.
sed -E '/^[[:space:]]*msg=\$\{msg\/\//d' "$B" > "$work/mutant.sh"
case "$(body "$(run "$work/mutant.sh" other '' 'boom 50% off')")" in
  *'50%25 off'*) fail "MUTANT no-escaping is not caught — the escaping case cannot discriminate" ;;
  *) pass "MUTANT no-escaping is caught" ;;
esac

echo
if [ "$fails" -eq 0 ]; then
  echo "test-renovate-reaper-merge: PASS — the reaper's merge lane merges, no-ops quietly, and fails loud"
  exit 0
fi
echo "test-renovate-reaper-merge: FAIL — $fails case(s) regressed" >&2
exit 1
