#!/usr/bin/env bash
# frameworks/gates/test-portable-shell.sh
# Asserts that no tracked shell source in this repo — and no bash body embedded in a YAML `run:`
# block — uses a spelling that fails on bash 3.2 / BSD userland. The rules, `scan()`, the YAML
# extractor and the file-list builders live in frameworks/gates/lib/portable-shell-scan.sh (sourced
# below); this file is the REAL SWEEP over the tree. The drills live in
# frameworks/gates/test-portable-shell-drills.sh, sourcing the same engine.
#
# WHY THIS EXISTS
# The defect class is "bash-4-only construct that fails SILENTLY and leaves rc 0": `${VAR,,}`,
# `declare -A`, `mapfile`, `shopt -s globstar`. A gate written with one of them does not go red on
# a 3.2 host — it degrades quietly and reports green, which is not a weaker signal than a red gate
# but a MISDIRECTED one. This repo already carries live instances: `declare -A SEVERITY_CHANNELS`
# in the workflow-engine escalation handler builds a severity→channel lookup that, on /bin/bash
# 3.2.57, collapses every key onto index 0 and routes every severity to one channel while exiting
# 0; and the `mapfile` DISCOVERY LOOP in .github/workflows/self-check.yml:234 is the very loop that
# enumerates and runs this fence. A discovery loop that cannot enumerate is the exact fail-open
# shape this fence exists to close, sitting one level above the fence.
#
# Those are being fixed by hand in PR #95. A point fix is not a fence: nothing in this repo would
# have caught them, and nothing would catch the next one. This sweep is the fence.
#
# WHY THE SCAN COVERS YAML `run:` BLOCKS TOO
# Embedded bash inside a `run:` step is not a `.sh` file, so a `.sh`-only glob never sees it — and
# that is where the worst instances of this class hide, because a `run:` body looks like CI-only
# code right up until an operator runs it locally. Workflow steps are deliberately NOT in scope for
# GNU/BSD spellings (they run on the ubuntu runner by design, so RULES_HOST stays `.sh`-only); that
# exemption does NOT extend to bash VERSION constructs, which are wrong wherever /bin/bash 3.2.57
# executes the body.
#
# WHAT THIS DOES NOT CHECK: `stat -c` vs `stat -f` (no rule — left to a dedicated portability lint
# rather than duplicated and disagreed with here), `"${arr[@]}"` under `set -u` on an empty array
# (a bash <4.4 unbound-variable trap, and the one thing PR #95 fixes that this fence does not
# cover — it needs array-shape analysis, not a spelling match), anything in an untracked file,
# anything under `frameworks/gates/fixtures/**` (see the lib's builders), and the SEMANTICS of any
# script — this is a spelling fence, not a correctness proof.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT" || { printf 'cannot cd to repo root\n'; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n     %s\n' "$1" "${2:-}"; }

printf '\n== portable shell (gate sources must run on bash 3.2 / BSD, not just the runner) ==\n'

# No `set -e` here, so mktemp failure must be checked by hand: an empty or missing SCRATCH would
# send every redirect below to paths like "/files" and turn the whole scan into noise that still
# reports green. A gate that cannot set up its own scratch space must say so and fail.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/portable-shell.XXXXXX")" || SCRATCH=""
if [ -z "$SCRATCH" ] || [ ! -d "$SCRATCH" ]; then
  bad "could not create a scratch directory under ${TMPDIR:-/tmp} — cannot verify, which is not clean"
  printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
  exit 1
fi
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/yamlmirror" || { bad "could not create $SCRATCH/yamlmirror — cannot verify"; printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"; exit 1; }

# shellcheck source=frameworks/gates/lib/portable-shell-scan.sh
. "$ROOT/frameworks/gates/lib/portable-shell-scan.sh"

n_files="$(psl_build_sh_files "$SCRATCH/files")"
if [ "${n_files:-0}" -eq 0 ]; then
  bad "no tracked shell sources matched — a scan that found nothing is not a pass" "check the git ls-files patterns in psl_build_sh_files"
  printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
  exit 1
fi

n_yaml_files="$(psl_build_yaml_files "$SCRATCH/yamlfiles")"
if [ "${n_yaml_files:-0}" -eq 0 ]; then
  bad "no tracked YAML files matched — a scan that found nothing is not a pass" "check the git ls-files patterns in psl_build_yaml_files"
  printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
  exit 1
fi

n_yaml_lines="$(psl_build_yaml_mirrors "$SCRATCH/yamlfiles" "$SCRATCH/yamlmirrorfiles")"
if [ "${n_yaml_lines:-0}" -eq 0 ]; then
  bad "extracted zero YAML run: block lines from $n_yaml_files tracked YAML file(s) — the extractor is broken, not the tree clean"
  printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
  exit 1
fi

# --- the real sweep ----------------------------------------------------------------------------
#
# RULES_HOST over `.sh` sources only (GNU/BSD spellings are correct in a `run:` block by design).
scan "$SCRATCH/files" "$SCRATCH/findings_host" "$RULES_HOST"

# RULES_BASHVER over `.sh` sources AND the YAML mirrors (bash-version constructs are wrong wherever
# `/bin/bash` 3.2.57 actually executes the body, and that is both).
cat "$SCRATCH/files" "$SCRATCH/yamlmirrorfiles" > "$SCRATCH/bashver_files"
scan "$SCRATCH/bashver_files" "$SCRATCH/findings_bashver_raw" "$RULES_BASHVER"
# Strip the mirror-root prefix so a YAML finding names the real repo path, not a temp file — a
# finding pointing at $SCRATCH/yamlmirror/... would send the next reader looking for a file that
# stops existing the moment this suite's EXIT trap fires.
sed "s#^$SCRATCH/yamlmirror/##" "$SCRATCH/findings_bashver_raw" > "$SCRATCH/findings_bashver"

cat "$SCRATCH/findings_host" "$SCRATCH/findings_bashver" > "$SCRATCH/findings"

# --- the dated baseline: a DEBT LEDGER, not an exemption list -----------------------------------
#
# See frameworks/gates/portable-shell-baseline.txt for the full rationale. In short: the findings
# this fence measured on main are enumerated there so it can land BLOCKING for everything else
# while PR #95's point fixes are still in flight. The baseline is keyed `<path>@@<the rule's full
# "why" text>` — path + rule class, not line number, so an unrelated insertion above a known site
# does not red a PR that did not cause it. The key is the rule text verbatim rather than a
# truncation or a short id: a hand-maintained abbreviation is one more thing that can silently stop
# matching, and a baseline that silently stops matching is a fence that silently stops fencing.
BASELINE="$ROOT/frameworks/gates/portable-shell-baseline.txt"
if [ ! -f "$BASELINE" ]; then
  bad "baseline file $BASELINE is missing — refusing to decide what is known debt and what is new"
  printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
  exit 1
fi
grep -v '^#' "$BASELINE" | grep . > "$SCRATCH/baseline" || : > "$SCRATCH/baseline"
n_baseline="$(grep -c . "$SCRATCH/baseline" 2>/dev/null || printf '0\n')"

: > "$SCRATCH/matched_baseline"
hits=0
while IFS= read -r finding; do
  [ -n "$finding" ] || continue
  loc="${finding%%@@*}"; rest="${finding#*@@}"
  why="${rest%%@@*}";    fix="${rest##*@@}"
  path="${loc%:*}"
  key="$path@@$why"
  if grep -qxF "$key" "$SCRATCH/baseline"; then
    printf '%s\n' "$key" >> "$SCRATCH/matched_baseline"
    continue
  fi
  hits=$((hits+1))
  bad "$loc — $why" "portable form: $fix"
done < "$SCRATCH/findings"

# STALE-ENTRY CHECK — the half that makes the baseline a SHRINKING ledger rather than a permanent
# exemption. A baselined site that no longer trips must be DELETED from the baseline in the same PR
# that fixes it; otherwise the entry silently outlives the debt and would quietly exempt a
# re-introduction of the same defect in the same file years later. When PR #95 merges, this check
# is what forces its Group A lines out of the ledger.
stale=0
while IFS= read -r key; do
  [ -n "$key" ] || continue
  if ! grep -qxF "$key" "$SCRATCH/matched_baseline" 2>/dev/null; then
    stale=$((stale+1))
    bad "STALE baseline entry: $key no longer trips" \
        "the debt is paid — delete this line from frameworks/gates/portable-shell-baseline.txt"
  fi
done < "$SCRATCH/baseline"

# The green coverage line is earned only when every rule ran against every file: a scan error
# already failed the suite above, and printing "0 unportable spellings" next to an unverified file
# would put a full-coverage claim in the transcript that the scan did not make. The count of
# still-baselined sites is printed on the green line ON PURPOSE — a debt ledger that is invisible
# when green is a debt ledger nobody pays down.
if [ "$hits" -eq 0 ] && [ "$stale" -eq 0 ] && [ "${scan_errors:-0}" -eq 0 ]; then
  ok "$n_files shell source(s) + $n_yaml_lines YAML run: line(s) across $n_yaml_files file(s) scanned, 0 NEW unportable spelling(s) ($n_baseline baselined site(s) still outstanding)"
fi

printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
