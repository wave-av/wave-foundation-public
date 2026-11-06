#!/usr/bin/env bash
# test-secret-scan-tempfiles.sh — a failed mktemp or a failed write to a temp file refuses and never
# reports clean, for both copies of the secret-scan gate. Harness and fake values:
# lib/secret-scan-harness.sh.
#
# Usage:  bash frameworks/gates/test-secret-scan-tempfiles.sh   (run by test-secret-scan.sh)
# Exit:   0 = every case behaved as specified · 1 = at least one case regressed.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/secret-scan-harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/secret-scan-harness.sh"

echo "== temp files — a failed mktemp refuses, it never reports clean =="

# A mktemp that counts its calls and fails call number MKTEMP_FAIL_AT. Zero never fails; `all` is a
# temp root that cannot be written, where every call fails. Call number MKTEMP_DENY_AT succeeds and
# names a file that cannot be written. A read-only mode does not stop root, so there it is a directory.
stub_dir="$work/mktemp-stub"
mkdir -p "$stub_dir"
cat > "$stub_dir/mktemp" <<'STUB'
#!/bin/sh
n=$(($(cat "$MKTEMP_COUNT_FILE") + 1))
printf '%s\n' "$n" > "$MKTEMP_COUNT_FILE"
case "$MKTEMP_FAIL_AT" in all|"$n") exit 1 ;; esac
made="$("$MKTEMP_REAL" "$@")" || exit 1
printf '%s\n' "$made" >> "$MKTEMP_MADE_FILE"
if [ "$MKTEMP_DENY_AT" = "$n" ]; then
  chmod 444 "$made"
  if [ "$(id -u)" -eq 0 ]; then rm -f "$made"; mkdir "$made"; fi
fi
printf '%s\n' "$made"
STUB
chmod +x "$stub_dir/mktemp"
real_mktemp="$(command -v mktemp)"
count_file="$work/mktemp-count"
made_file="$work/mktemp-made"

# stub_mktemp <call> [<deny>] — the next run fails mktemp call <call> and cannot write the file of
# call <deny>.
stub_mktemp() {
  printf '0\n' > "$count_file"
  : > "$made_file"
  gate_env=("${no_ci_env[@]}" "PATH=$stub_dir:$PATH" "MKTEMP_REAL=$real_mktemp"
    "MKTEMP_COUNT_FILE=$count_file" "MKTEMP_MADE_FILE=$made_file" "MKTEMP_FAIL_AT=$1"
    "MKTEMP_DENY_AT=${2:-0}")
}

# Z1 fails each call in turn, so a temp file added later is covered without changing this list. The
# tree holds a key, because reporting that tree clean is the regression. Z0 is the control: the stub
# passes through, and it is what measures how many calls there are.
t="$(shape_tree z "const k = '$canary';")"
for runner in run_script run_inline; do
  stub_mktemp 0
  check_one "Z0 mktemp works, key in the tree [$runner]   -> detected" "$runner" 1 "do not commit credentials" "$t"
  calls="$(cat "$count_file")"
  if [ "$calls" -ge 1 ]; then pass "Z0 the gate calls mktemp [$runner]"; else fail "Z0 the gate calls mktemp [$runner]"; fi
  for ((call = 1; call <= calls; call++)); do
    stub_mktemp "$call"
    check_one "Z1 mktemp call $call of $calls fails [$runner]    -> refused" "$runner" 1 "could not create a temp file" "$t"
    leftover=0
    while IFS= read -r made; do
      [ ! -e "$made" ] || leftover=1
    done < "$made_file"
    if [ "$leftover" -eq 0 ]; then pass "Z2 mktemp call $call fails, nothing left behind [$runner]"
    else fail "Z2 mktemp call $call fails, nothing left behind [$runner]"; fi
  done
  stub_mktemp all
  check_one "Z3 every mktemp call fails [$runner]    -> refused" "$runner" 1 "could not create a temp file" "$t"
done
gate_env=("${no_ci_env[@]}")

echo "== temp files — a failed write refuses, it never reports clean =="

refused="could not write a temp file"
limit=0
# shellcheck disable=SC2329 # check_one calls these by name
limited_script() { (ulimit -f "$limit"; run_script "$1"); }
# shellcheck disable=SC2329 # check_one calls these by name
limited_inline() { (ulimit -f "$limit"; run_inline "$1"); }

# A change that makes the gate write all of its temp files: an allowlist on the base, an exception
# that reads the base copy of a file, and a finding.
full="$(pr_tree z-full)"
full_base="$(base_of "$full")"
plant "$full" src/new.js
# The same when the allowlist and the file are both absent on the base, where each copy is an empty file.
absent="$(pr_tree z-absent)"
git_t "$absent" rm -q .github/.secret-allowlist docs/EXAMPLE.md
git_t "$absent" commit -q -m drop
absent_base="$(base_of "$absent")"
printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$absent/src/new.js"
# A key with no allowlist and no base, which leaves the allowlist copy and the base copy unwritten.
bare="$(shape_tree z-bare "const k = '$canary';")"
clean="$(shape_tree z-clean "const k = 1;")"

for runner in run_script run_inline; do
  stub_mktemp 0
  "$runner" "$bare" > /dev/null
  calls="$(cat "$count_file")"

  # Z4 — each file in turn, on the run that writes them all.
  for ((call = 1; call <= calls; call++)); do
    stub_mktemp 0 "$call"
    gate_env+=(GITHUB_EVENT_NAME=pull_request "PR_BASE_SHA=$full_base")
    check_one "Z4 temp file $call of $calls unwritable, change [$runner] -> refused" "$runner" 1 "$refused" "$full"
    stub_mktemp 0 "$call"
    gate_env+=(GITHUB_EVENT_NAME=pull_request "PR_BASE_SHA=$absent_base")
    check_one "Z4a temp file $call of $calls unwritable, absent on base [$runner] -> refused" "$runner" 1 "$refused" "$absent"
  done

  # Z5-Z6 — a file a run has no need to write is not a failed write, so that run still reports the
  # key. Every run exits 1, and the number of refusals is the number of files that run writes.
  for mode in push bare; do
    tree="$full"; want="$((calls - 1))"
    if [ "$mode" = bare ]; then tree="$bare"; want="$((calls - 2))"; fi
    refusals=0
    for ((call = 1; call <= calls; call++)); do
      stub_mktemp 0 "$call"
      gate_env+=(GITHUB_EVENT_NAME=push)
      check_one "Z5 temp file $call of $calls unwritable, $mode [$runner] -> not clean" "$runner" 1 "" "$tree"
      printf '0\n' > "$count_file"
      if [[ "$("$runner" "$tree")" == *"$refused"* ]]; then refusals=$((refusals + 1)); fi
    done
    if [ "$refusals" -eq "$want" ]; then pass "Z6 $mode run refuses for each file it writes [$runner]"
    else fail "Z6 $mode run refuses for each file it writes [$runner] — $refusals, want $want"; fi
  done
done
gate_env=("${no_ci_env[@]}")

# Z7-Z10 — a file limit: the temp file opens, and only the write itself fails.
for runner in limited_script limited_inline; do
  gate_env=("${no_ci_env[@]}")
  check_one "Z7 ulimit -f 0, key, no allowlist [$runner] -> refused" "$runner" 1 "$refused" "$bare"
  gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=push)
  check_one "Z8 ulimit -f 0, push, allowlist [$runner] -> refused" "$runner" 1 "$refused" "$full"
  gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=pull_request "PR_BASE_SHA=$full_base")
  check_one "Z9 ulimit -f 0, change [$runner] -> refused" "$runner" 1 "$refused" "$full"
  # The control: nothing to write, so nothing failed. A gate that fails every tree does not pass this.
  gate_env=("${no_ci_env[@]}")
  check_one "Z10 ulimit -f 0, clean tree, no allowlist [$runner] -> clean" "$runner" 0 "secret-scan clean" "$clean"
done

# Z11 — the limit lets the small files through and stops only the base copy of a large file. The
# line is unchanged, so with the copy written this run is clean.
large="$(pr_tree z-large)"
{
  for ((i = 0; i < 400; i++)); do printf 'harmless padding line\n'; done
  printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary"
} > "$large/src/large.js"
git_t "$large" add -A
git_t "$large" commit -q -m large
gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=pull_request "PR_BASE_SHA=$(base_of "$large")")
both "Z11 no limit, large base copy       -> clean" 0 "secret-scan clean" "$large"
limit=1
check_one "Z11 ulimit -f 1, large base copy [limited_script] -> refused" limited_script 1 "$refused" "$large"
check_one "Z11 ulimit -f 1, large base copy [limited_inline] -> refused" limited_inline 1 "$refused" "$large"
gate_env=("${no_ci_env[@]}")

finish "secret-scan temp files"
