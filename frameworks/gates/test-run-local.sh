#!/usr/bin/env bash
# test-run-local.sh — self-test for the local-CI receipt WRITER. (#967.)
#
# The chain had three parts and the one that PRODUCES the evidence had no drill:
#
#   run-local.sh      writes the receipt        <- untested
#   verify-receipt.sh reads and certifies it    <- test-verify-receipt.sh, 11 cases
#   pre-push.sh       invokes the writer        <- test-pre-push.sh
#
# Every property the verifier checks is a property the writer is responsible for emitting, and the
# verifier's fixtures are built BY HAND. That is right for a reader — it can then exercise malformed
# receipts a real writer would never produce — but it means those fixtures encode an UNDERSTANDING of
# the format rather than the writer's behaviour. The two halves could drift apart without a single
# test going red. This suite is the round trip that ties them together: the writer's real output,
# fed to the real verifier.
#
# WHY IT CAN RUN AT ALL. run-local.sh rsyncs to a remote host and execs docker, so it cannot be
# executed here. #967 extracted the receipt derivation into lib/waveci-common.sh precisely so the
# format has one definition and that definition is reachable without a network. What is NOT covered,
# said plainly: the rsync, the container invocation, and the exit-code mapping around docker. Those
# still need a runner host. Everything about the RECEIPT is covered.
#
# Every case runs inside a throwaway git repo under mktemp -d, with WAVECI_RECEIPTS pointed into the
# same temp dir — the real receipt store is never read or written.
#
# Usage:  bash frameworks/gates/test-run-local.sh
# Exit:   0 = every case behaved as specified · 1 = at least one regressed.
#
# SC1090: the mutants are generated into a temp dir at run time, so their paths cannot be constant —
# that is the entire point of a mutant. This directive must sit BEFORE the first command to apply
# file-wide; placed after one it binds only to the next command, which is how the first attempt at
# the same directive in test-check-file-size.sh silently did nothing.
# shellcheck disable=SC1090
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/scripts/lib/waveci-common.sh"
VERIFY="$HERE/scripts/verify-receipt.sh"
for f in "$LIB" "$VERIFY"; do
  [ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }
done
# shellcheck source=frameworks/gates/scripts/lib/waveci-common.sh
. "$LIB"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export WAVECI_RECEIPTS="$work/receipts"
mkdir -p "$WAVECI_RECEIPTS"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }
check() { # check <case> <want> <got>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '       want %s\n       got  %s\n' "$2" "$3"; fi
}

# ── the fixture repo ─────────────────────────────────────────────────────────────────────────────
# Real gate scripts, a real registry, a real commit — but all synthetic, so a change to the actual
# gate set cannot make this suite pass or fail for an unrelated reason. The second gate's id is
# deliberately NOT its filename (`beta` -> `check-beta.sh`), which is the mapping that left
# run-local.sh's own default invocation broken from the day it shipped.
FIX="$work/repo"
mkdir -p "$FIX/frameworks/gates/scripts"
cat >"$FIX/frameworks/gates/registry.yaml" <<'YAML'
gates:
  - id: alpha
    script: frameworks/gates/scripts/alpha.sh
  - id: beta
    script: frameworks/gates/scripts/check-beta.sh
YAML
echo 'echo alpha ok' >"$FIX/frameworks/gates/scripts/alpha.sh"
echo 'echo beta ok'  >"$FIX/frameworks/gates/scripts/check-beta.sh"
echo 'tracked' >"$FIX/tracked.txt"
(
  cd "$FIX" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  git remote add origin git@example.com:wave-av/fixture-repo.git
  git add -- frameworks tracked.txt
  git commit -qm 'fixture'
) || { echo "error: could not build the fixture repo" >&2; exit 1; }

cd "$FIX" || exit 1
SHA=$(git rev-parse HEAD)
REPO=$(waveci_repo_name "$FIX")

# rows_now — build the gate rows the way run-local.sh does: hash the WORKING TREE copy of each gate
# script, because the working tree is what gets rsynced and therefore what runs. Both call
# waveci_gate_row, so the row shape is not re-typed here; a re-typed copy would be a third
# implementation that can agree with this test while disagreeing with what actually gets written.
rows_now() {
  # Named `built`, not `out`: a local array sharing a name with the string `out` used later for
  # command output makes shellcheck read the two as one variable (SC2178/SC2128) and warn on every
  # later use. The warning is a false positive across scopes, but a suite that ships warnings trains
  # readers to skim them.
  local built=() gid script
  while IFS=$'\t' read -r gid script; do
    [ -n "$gid" ] || continue
    built+=("$(waveci_gate_row "$gid" "$(shasum -a 256 "$script" | cut -d' ' -f1)" 0 "$(printf '' | shasum -a 256 | cut -d' ' -f1)")")
  done < <(waveci_registry_gates)
  printf '%s\n' ${built[@]+"${built[@]}"}
}

# write_receipt — the writer path end to end, minus docker: derive tree state, derive the path, emit
# the JSON. Prints the path it wrote.
write_receipt() {
  local dirty tree_id path rows=()
  IFS=$'\t' read -r dirty tree_id < <(waveci_tree_state)
  while IFS= read -r r; do [ -n "$r" ] && rows+=("$r"); done < <(rows_now)
  path="$(waveci_receipt_path "$WAVECI_RECEIPTS" "$REPO" "$SHA" "$dirty" "$tree_id")"
  waveci_receipt_json "$REPO" "$SHA" "$dirty" "$tree_id" \
    "root@fixture" "debian@sha256:$(printf 'i' | shasum -a 256 | cut -d' ' -f1)" \
    "2026-07-30T00:00:00Z" ${rows[@]+"${rows[@]}"} >"$path"
  printf '%s' "$path"
}

echo "== A. the round trip — the writer's real output must satisfy the real verifier =="

# A0 — run-local.sh runs under `set -euo pipefail` and consumes this with
# `read -r DIRTY TREE_ID < <(waveci_tree_state)`. `read` returns 1 when it reaches EOF without
# hitting its delimiter, so a function that prints an UNTERMINATED line assigns both variables
# correctly and THEN kills the runner on the next statement. Invisible to every other consumer and
# to every other case in this file, because none of them set -e. Not hypothetical: extracting the
# function in #967 introduced exactly this, and this case is what caught it.
#
# The probe is a FILE, not a `bash -c` string: the first attempt at it nested three levels of
# quoting, silently changed what was being executed, and reported the broken form as surviving. A
# test whose subject is shell semantics must not put a quoting layer between itself and them.
cat >"$work/a0-probe.sh" <<'SH'
. "$1"
IFS=$'\t' read -r d t < <(waveci_tree_state)
printf 'survived\t%s\t%s\n' "$d" "$t"
SH
a0() { bash -euo pipefail "$work/a0-probe.sh" "$1" 2>/dev/null; }

case "$(a0 "$LIB")" in
  survived*) pass "A0 survives \`read\` under set -e, the way run-local.sh calls it" ;;
  *) fail "A0 survives \`read\` under set -e, the way run-local.sh calls it" ;;
esac

# DISCRIMINATION for A0 — strip the newline back off and the probe must die before printing.
MUT_NONL="$work/mutant-nonl.sh"
python3 - "$LIB" "$MUT_NONL" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
assert src.count("\\tclean\\n'") == 1 and src.count("dirty-%s\\n'") == 1, "mutant targets moved"
pathlib.Path(sys.argv[2]).write_text(src.replace("\\tclean\\n'", "\\tclean'").replace("dirty-%s\\n'", "dirty-%s'"))
PY
if [ -z "$(a0 "$MUT_NONL")" ]; then
  pass "A0m MUTANT (no trailing newline) dies under set -e — the case discriminates"
else
  fail "A0m MUTANT (no trailing newline) dies under set -e — it survived, so A0 proves nothing"
fi

CLEAN_RECEIPT="$(write_receipt)"
check "A1 clean run writes <repo>-<sha>.json" "$WAVECI_RECEIPTS/${REPO}-${SHA}.json" "$CLEAN_RECEIPT"

out="$(bash "$VERIFY" "$SHA" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "VERIFIED $SHA"; then
  pass "A2 verify-receipt VERIFIES it"
else
  fail "A2 verify-receipt VERIFIES it — exit $rc"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"
fi

# The claim from #937 that nothing asserted: gate_file_sha256 must equal the hash of the gate script
# AS OF THE COMMIT. The writer hashes the working tree; the verifier recomputes from `git show`. On a
# clean tree those must be the same number, and A2 above already depends on it — this states it
# directly so a failure names the cause instead of surfacing as a generic UNVERIFIED.
tree_hash=$(shasum -a 256 frameworks/gates/scripts/alpha.sh | cut -d' ' -f1)
blob_hash=$(git show "$SHA:frameworks/gates/scripts/alpha.sh" | shasum -a 256 | cut -d' ' -f1)
check "A3 gate_file_sha256 == the blob at that commit" "$blob_hash" "$tree_hash"

# `dirty` must be a JSON boolean. verify-receipt.sh tests `d.get("dirty") is not False`, so a
# "false" STRING makes every receipt silently unverifiable and the failure reads as a verifier bug.
got=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("bool-false" if d["dirty"] is False else repr(d["dirty"]))' "$CLEAN_RECEIPT")
check "A4 dirty is JSON false, not \"false\"" "bool-false" "$got"

echo "== B. a dirty run must not be able to overwrite or impersonate a clean one (#934) =="

CLEAN_BEFORE=$(shasum -a 256 "$CLEAN_RECEIPT" | cut -d' ' -f1)
echo 'edited' >>tracked.txt

DIRTY_RECEIPT="$(write_receipt)"
if [ "$DIRTY_RECEIPT" != "$CLEAN_RECEIPT" ]; then pass "B1 dirty run writes a DIFFERENT filename"
else fail "B1 dirty run writes a DIFFERENT filename — it overwrote $CLEAN_RECEIPT"; fi

case "$DIRTY_RECEIPT" in
  *"-${SHA}-dirty-"*) pass "B2 the dirty filename carries the tree fingerprint" ;;
  *) fail "B2 the dirty filename carries the tree fingerprint"; printf '       got  %s\n' "$DIRTY_RECEIPT" ;;
esac

check "B3 the clean receipt is untouched" "$CLEAN_BEFORE" "$(shasum -a 256 "$CLEAN_RECEIPT" | cut -d' ' -f1)"

got=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("bool-true" if d["dirty"] is True else repr(d["dirty"]))' "$DIRTY_RECEIPT")
check "B4 dirty is JSON true on a dirty run" "bool-true" "$got"

# The verifier consults ONLY the clean name, so the still-valid clean receipt keeps verifying and the
# dirty one is unreachable by construction. That is the design: a receipt attesting uncommitted
# content cannot vouch for a commit, whatever its gates reported.
out="$(bash "$VERIFY" "$SHA" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then pass "B5 the clean receipt still verifies"
else fail "B5 the clean receipt still verifies — exit $rc"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"; fi

# And with no clean receipt present, a dirty receipt must NOT stand in for it. This is the case the
# whole filename split exists for: before #935 the dirty run landed on the clean name and this read
# as a pass.
mv "$CLEAN_RECEIPT" "$work/parked.json"
out="$(bash "$VERIFY" "$SHA" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "no receipt for"; then
  pass "B6 a dirty receipt alone -> UNVERIFIED"
else
  fail "B6 a dirty receipt alone -> UNVERIFIED — exit $rc"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"
fi
mv "$work/parked.json" "$CLEAN_RECEIPT"
git checkout -q -- tracked.txt

echo "== C. the tree fingerprint must not lose resolution to NUL-stripping =="

# `git status --porcelain=v1 -z` separates records with NUL. Capturing that into a variable strips
# the NULs (bash warns), running the records together — so two genuinely different dirty states can
# hash alike, and a fingerprint that quietly loses resolution is worse than none because it still
# looks authoritative. This is a REAL collision pair, not an illustration: one untracked file named
# `x?? y` and two untracked files `x` and `y` produce identical bytes once the NULs are gone.
#
#   one file:   "?? x?? y\0"
#   two files:  "?? x\0" "?? y\0"      -> NULs stripped, both are "?? x?? y"
COL="$work/collide"
mkdir -p "$COL"
(
  cd "$COL" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name t
  git config commit.gpgsign false
  echo seed >seed.txt
  git add -- seed.txt
  git commit -qm seed
) >/dev/null 2>&1

state_a() { rm -f "$COL/x" "$COL/y" "$COL/x?? y"; : >"$COL/x?? y"; }
state_b() { rm -f "$COL/x" "$COL/y" "$COL/x?? y"; : >"$COL/x"; : >"$COL/y"; }

cd "$COL" || exit 1
state_a; A=$(waveci_tree_state)
state_b; B=$(waveci_tree_state)
if [ "$A" != "$B" ]; then pass "C1 the two dirty states fingerprint DIFFERENTLY"
else fail "C1 the two dirty states fingerprint DIFFERENTLY — both '$A'"; fi

# DISCRIMINATION. A case that passes against a broken implementation proves nothing, so the broken
# implementation is built and run. The mutant restores the command-substitution form; it must make
# C1's pair collide, and it must leave the clean/dirty verdict itself alone (or the mutant would be
# too broad to attribute anything to).
MUT="$work/mutant-nul.sh"
python3 - "$LIB" "$MUT" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
old = '"$(git status --porcelain=v1 -z 2>/dev/null | shasum -a 256 | cut -c1-12)"'
new = '"$(printf %s "$(git status --porcelain=v1 -z 2>/dev/null)" | shasum -a 256 | cut -c1-12)"'
assert src.count(old) == 1, f"mutant target matched {src.count(old)} times, want 1"
pathlib.Path(sys.argv[2]).write_text(src.replace(old, new))
PY
if [ -f "$MUT" ]; then
  state_a; MA=$( . "$MUT"; waveci_tree_state 2>/dev/null )
  state_b; MB=$( . "$MUT"; waveci_tree_state 2>/dev/null )
  if [ "$MA" = "$MB" ]; then pass "C2 MUTANT (command substitution) collides — the case discriminates"
  else fail "C2 MUTANT (command substitution) collides — it did not, so C1 proves nothing"; fi
  rm -f "$COL/x" "$COL/y" "$COL/x?? y"
  MC=$( . "$MUT"; waveci_tree_state )
  check "C3 MUTANT control: a clean tree still reads clean" "$(printf 'false\tclean')" "$MC"
else
  fail "C2 MUTANT (command substitution) collides — could not build the mutant"
fi

cd "$FIX" || exit 1

echo "== D. mutants of the writer must break the round trip =="

# D1 — the filename split is what stops #934. A mutant that always uses the clean name reproduces the
# original corruption: the dirty run lands on the clean receipt and overwrites it.
MUT_PATH="$work/mutant-path.sh"
python3 - "$LIB" "$MUT_PATH" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
old = """  if [ "$4" = true ]; then printf '%s/%s-%s-%s.json' "$1" "$2" "$3" "$5"
  else printf '%s/%s-%s.json' "$1" "$2" "$3"; fi"""
new = """  printf '%s/%s-%s.json' "$1" "$2" "$3\""""
assert src.count(old) == 1, f"mutant target matched {src.count(old)} times, want 1"
pathlib.Path(sys.argv[2]).write_text(src.replace(old, new))
PY
got=$( . "$MUT_PATH"; waveci_receipt_path /r repo aaaa true dirty-abc )
check "D1 MUTANT (no filename split) collides onto the clean name" "/r/repo-aaaa.json" "$got"

# D2 — `dirty` as a quoted string. The verifier's `is not False` then never matches and EVERY receipt
# reads unverified, which is exactly the failure that would be misdiagnosed as a verifier bug. Run it
# through the real verifier rather than asserting on the JSON text, so the case measures consequence.
MUT_BOOL="$work/mutant-bool.sh"
python3 - "$LIB" "$MUT_BOOL" <<'PY'
import sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text()
old = '\'{"repo":"%s","sha":"%s","dirty":%s,'
new = '\'{"repo":"%s","sha":"%s","dirty":"%s",'
assert src.count(old) == 1, f"mutant target matched {src.count(old)} times, want 1"
pathlib.Path(sys.argv[2]).write_text(src.replace(old, new))
PY
(
  . "$MUT_BOOL"
  rows=()
  while IFS= read -r r; do [ -n "$r" ] && rows+=("$r"); done < <(rows_now)
  waveci_receipt_json "$REPO" "$SHA" false clean h i t ${rows[@]+"${rows[@]}"} \
    >"$WAVECI_RECEIPTS/${REPO}-${SHA}.json"
)
out="$(bash "$VERIFY" "$SHA" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "DIRTY"; then
  pass "D2 MUTANT (dirty as a string) -> UNVERIFIED, so A4 discriminates"
else
  fail "D2 MUTANT (dirty as a string) -> UNVERIFIED — exit $rc"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"
fi

# Restore a good receipt, then prove waveci_receipt_json refuses a non-boolean outright — the writer
# should not be able to emit that shape in the first place.
write_receipt >/dev/null
out=$(waveci_receipt_json r s maybe clean h i t 2>&1); rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF "must be true|false"; then
  pass "D3 a non-boolean dirty is refused at the writer"
else
  fail "D3 a non-boolean dirty is refused at the writer — exit $rc"
fi

echo "== E. the shared input validators, which guard path construction =="

# waveci_sha_ok and waveci_repo_name_ok gate a `git show` argument, an `rsync --delete` destination
# and a receipt filename. Neither had a direct case: the verifier's traversal case exercises
# waveci_gate_id_ok, and these two were reached only incidentally. A shared validator that each
# consumer tests "a bit" is how a validator quietly loosens.
ok_sha() { waveci_sha_ok "$1" && echo yes || echo no; }
ok_repo() { waveci_repo_name_ok "$1" && echo yes || echo no; }

check "E1 40 lowercase hex accepted"        yes "$(ok_sha "$(printf 'a%.0s' $(seq 40))")"
check "E2 short sha rejected"               no  "$(ok_sha abc1234)"
check "E3 uppercase hex rejected"           no  "$(ok_sha "$(printf 'A%.0s' $(seq 40))")"
check "E4 41 hex rejected"                  no  "$(ok_sha "$(printf 'a%.0s' $(seq 41))")"
check "E5 plain repo name accepted"         yes "$(ok_repo wave-foundation)"
check "E6 empty rejected"                   no  "$(ok_repo "")"
check "E7 .. rejected (traversal)"          no  "$(ok_repo "..")"
check "E8 a/b rejected (path segment)"      no  "$(ok_repo "a/b")"
check "E9 shell metacharacters rejected"    no  "$(ok_repo 'x;rm -rf /')"

cd "$REPO_ROOT" || exit 1
echo
if [ "$fails" -eq 0 ]; then
  echo "test-run-local: PASS — the writer's output round-trips through the real verifier"
  exit 0
fi
echo "test-run-local: FAIL — $fails case(s) regressed" >&2
exit 1
