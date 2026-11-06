#!/usr/bin/env bash
# test-secret-scan-line-entries.sh — an allowlist entry that names one line, as path:line, for both
# copies of the secret-scan gate. Harness and fake values: lib/secret-scan-harness.sh.
#
# Usage:  bash frameworks/gates/test-secret-scan-line-entries.sh   (run by test-secret-scan.sh)
# Exit:   0 = every case behaved as specified · 1 = at least one case regressed.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/secret-scan-harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/secret-scan-harness.sh"

# plant_at <tree> <path> <line> — puts a key shape on <line> of <path>, after harmless lines.
plant_at() {
  local i
  mkdir -p "$1/$(dirname "$2")"
  {
    for ((i = 1; i < $3; i++)); do printf 'hello\n'; done
    printf 'const k = "%s";\n' "$canary"
  } > "$1/$2"
}

# on_base <tree> — commits what the tree holds, so the run after it sees those lines as unchanged.
on_base() { git_t "$1" add -A; git_t "$1" commit -q -m line; }

echo "== line entries — path:line names one line, compared whole, never as a substring =="

# Y11 — with or without the trailing colon the old match over grep's path:line: record needed.
t="$(pr_tree_with y11 src/new.js:1)"
plant "$t" src/new.js; on_base "$t"; on_pr "$(base_of "$t")"
both "Y11 path:line entry                 -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y11a src/new.js:1:)"
plant "$t" src/new.js; on_base "$t"; on_pr "$(base_of "$t")"
both "Y11a path:line: entry               -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y11b src/new.js:1)"; on_pr "$(base_of "$t")"
plant_at "$t" src/new.js 2
both "Y11b path:line entry, other line    -> detected" 1 "./src/new.js:2" "$t"

t="$(pr_tree_with y11c src/new.js:1)"
plant "$t" src/new.js; on_base "$t"; on_pr "$(base_of "$t")"
printf 'const j = "%s";\n' "$canary" >> "$t/src/new.js"
both "Y11c listed line and another        -> second detected" 1 "./src/new.js:2" "$t"
never_prints "Y11c listed line is not reported" "./src/new.js:1" "$t"

t="$(pr_tree_with y11d src/new.js:1)"; on_pr "$(base_of "$t")"
plant_at "$t" src/new.js 10
both "Y11d line 1 entry, key on line 10   -> detected" 1 "./src/new.js:10" "$t"

t="$(pr_tree_with y11e src/new.js:10)"; on_pr "$(base_of "$t")"
plant "$t" src/new.js
both "Y11e line 10 entry, key on line 1   -> detected" 1 "./src/new.js:1" "$t"

t="$(pr_tree_with y11f new.js:1)"; on_pr "$(base_of "$t")"
plant "$t" src/new.js
both "Y11f entry is the end of a path:line -> detected" 1 "./src/new.js:1" "$t"

t="$(pr_tree_with y11g src/new.js:1)"; on_pr "$(base_of "$t")"
plant "$t" x/src/new.js
both "Y11g same path:line, deeper file    -> detected" 1 "./x/src/new.js:1" "$t"

t="$(pr_tree_with y11h src/new.js:1)"; on_pr "$(base_of "$t")"
plant "$t" src/new.js:1.ts
both "Y11h file named entry plus a suffix -> detected" 1 "./src/new.js:1.ts:1" "$t"

t="$(pr_tree_with y11i src/new.js:)"; on_pr "$(base_of "$t")"
plant "$t" src/new.js
both "Y11i path: entry, no line number    -> detected" 1 "./src/new.js:1" "$t"

t="$(pr_tree_with y11j src/new.js:1::)"; on_pr "$(base_of "$t")"
plant "$t" src/new.js
both "Y11j two trailing colons            -> detected" 1 "./src/new.js:1" "$t"

# private-repo's reviewed entry, byte for byte, on the line it names and on its neighbour.
rig_entry=bench/righttest/results/studio-guard-vision-2026-09-26/guard/guard_v2.jsonl:831:
rig_path=bench/righttest/results/studio-guard-vision-2026-09-26/guard/guard_v2.jsonl
t="$(pr_tree_with y11k "$rig_entry")"
plant_at "$t" "$rig_path" 831; on_base "$t"; on_pr "$(base_of "$t")"
both "Y11k private-repo entry, line 831       -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y11l "$rig_entry")"; on_pr "$(base_of "$t")"
plant_at "$t" "$rig_path" 830
both "Y11l private-repo entry, line 830       -> detected" 1 "./$rig_path:830" "$t"

t="$(pr_tree_with y11m src/a:b.js:1)"
plant "$t" src/a:b.js; on_base "$t"; on_pr "$(base_of "$t")"
both "Y11m colon in the listed path       -> clean" 0 "secret-scan clean" "$t"

# The entry takes effect once it is on the base, like every other exception.
t="$(pr_tree y11n)"; on_pr "$(base_of "$t")"
plant "$t" src/new.js
printf 'src/new.js:1\n' >> "$t/.github/.secret-allowlist"
both "Y11n entry in the same change       -> detected" 1 "./src/new.js:1" "$t"

# An entry that reads as path:line names a line, never a file of that name. A change could otherwise
# add the file and exempt whatever it holds.
t="$(pr_tree_with y11s src/app.js:1)"; on_pr "$(base_of "$t")"
plant "$t" src/app.js:1
both "Y11s new file named path:line entry -> detected" 1 "./src/app.js:1:1" "$t"

t="$(pr_tree_with y11t src/app.js:1:)"; on_pr "$(base_of "$t")"
plant "$t" src/app.js:1:
both "Y11t new file named path:line: entry -> detected" 1 "./src/app.js:1::1" "$t"

t="$(pr_tree_with y11u src/app.js:1)"; on_pr "$(base_of "$t")"
plant "$t" src/app.js:1/inner.js
both "Y11u new directory named the entry  -> detected" 1 "./src/app.js:1/inner.js:1" "$t"

t="$(pr_tree_with y11v src/app.js:1)"
plant "$t" src/app.js:1; on_base "$t"; on_pr "$(base_of "$t")"
both "Y11v such a file already on the base -> detected" 1 "./src/app.js:1:1" "$t"

# The colon alone does not make it a line entry: this one still names the whole file.
t="$(pr_tree_with y11w src/a:b.js)"; on_pr "$(base_of "$t")"
plant "$t" src/a:b.js
both "Y11w whole-path entry with a colon  -> clean" 0 "secret-scan clean" "$t"

gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=push)
t="$(pr_tree_with y11o src/new.js:1)"; plant "$t" src/new.js
both "Y11o tree: path:line entry          -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y11p src/new.js:1)"; plant_at "$t" src/new.js 2
both "Y11p tree: path:line, other line    -> detected" 1 "./src/new.js:2" "$t"

# The script's stale-entry note reads the path out of a path:line entry. Only the script has the note.
t="$(pr_tree_with y11q src/new.js:1:)"; plant "$t" src/new.js
out="$(run_script "$t")"
if [[ "$out" != *"stale exception"* ]]; then pass "Y11q live path:line entry is not called stale"
else fail "Y11q live path:line entry is not called stale"; fi
check_one "Y11r path:line entry, path is gone   -> stale note" run_script 0 "stale exception" "$(pr_tree_with y11r src/gone.js:1)"
gate_env=("${no_ci_env[@]}")

echo "== line entries — on a change, the listed line must be unchanged from the base =="

other_key="AKIA$(printf 'ZYXWVUTSRQPONMLK')"
# replace_line <tree> <path> <line> — puts a different key shape on <line>, after harmless lines.
replace_line() {
  local i
  {
    for ((i = 1; i < $3; i++)); do printf 'hello\n'; done
    printf 'const k = "%s";\n' "$other_key"
  } > "$1/$2"
}

# Y21 — what the entry was reviewed for, with the rest of the file edited around it.
t="$(pr_tree_with y21 src/new.js:1)"
plant "$t" src/new.js; on_base "$t"; on_pr "$(base_of "$t")"
printf 'hello\n' >> "$t/src/new.js"
both "Y21 listed line unchanged, file edited -> clean" 0 "secret-scan clean" "$t"

# Y22-Y24 — the same entry with a new value on the line.
t="$(pr_tree_with y22 src/new.js:1)"
plant "$t" src/new.js; on_base "$t"; on_pr "$(base_of "$t")"
replace_line "$t" src/new.js 1
both "Y22 listed line replaced            -> detected" 1 "./src/new.js:1" "$t"
never_prints "Y22 new value is not printed" "$other_key" "$t"

t="$(pr_tree_with y23 "$rig_entry")"
plant_at "$t" "$rig_path" 831; on_base "$t"; on_pr "$(base_of "$t")"
replace_line "$t" "$rig_path" 831
both "Y23 private-repo entry, line 831 replaced -> detected" 1 "./$rig_path:831" "$t"

t="$(pr_tree_with y24 src/a:b.js:1:)"
plant "$t" src/a:b.js; on_base "$t"; on_pr "$(base_of "$t")"
replace_line "$t" src/a:b.js 1
both "Y24 colon in the path, line replaced -> detected" 1 "./src/a:b.js:1" "$t"

# Y25 — the file is on the base and the key is new to it. Y26 — the file is not on the base at all.
t="$(pr_tree_with y25 src/app.js:1)"; on_pr "$(base_of "$t")"
plant "$t" src/app.js
both "Y25 key new on a listed line        -> detected" 1 "./src/app.js:1" "$t"

t="$(pr_tree_with y26 src/new.js:1)"; on_pr "$(base_of "$t")"
plant "$t" src/new.js
both "Y26 listed file only in the change  -> detected" 1 "./src/new.js:1" "$t"

# Y27 — the merge queue reads its own base variable, with the same result both ways.
t="$(pr_tree_with y27 src/new.js:1)"
plant "$t" src/new.js; on_base "$t"; on_queue "$(base_of "$t")"
both "Y27 merge queue, line unchanged     -> clean" 0 "secret-scan clean" "$t"
replace_line "$t" src/new.js 1
both "Y27 merge queue, line replaced      -> detected" 1 "./src/new.js:1" "$t"

# Y28 — a whole-path entry keeps its stated limit: it exempts changed content in the file.
t="$(pr_tree y28)"; on_pr "$(base_of "$t")"
replace_line "$t" docs/EXAMPLE.md 1
both "Y28 whole-path entry, line replaced -> clean" 0 "secret-scan clean" "$t"
gate_env=("${no_ci_env[@]}")

finish "secret-scan line entries"
