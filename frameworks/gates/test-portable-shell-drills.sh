#!/usr/bin/env bash
# frameworks/gates/test-portable-shell-drills.sh
# The drills for this repo's bash-3.2 portability fence. The rules tables, `scan()`, the YAML `run:`
# extractor and `build_mirror()` all live in frameworks/gates/lib/portable-shell-scan.sh, sourced
# below — every drill here calls THAT real code, not a re-typed copy. This is not incidental: a
# drill only proves anything if it exercises the same path the real sweep
# (frameworks/gates/test-portable-shell.sh) runs, so a rule that quietly breaks or a loop that goes
# inert fails a drill here too. See the lib's own header for the full statement of this invariant.
#
# THE SCAN MUST BE ABLE TO FAIL, or a green result means nothing. That is the entire reason this
# file exists alongside the sweep. A fence that cannot go red is worse than no fence — it reports
# coverage it does not have, which is the same failure one layer up.
#
# Each drill below runs the REAL scan over a fixture carrying one known-bad (or known-clean)
# spelling — never a hand-retyped copy of the pattern, which would keep passing even if the rule
# were deleted. The last four drills pin the two FALSE POSITIVES this port deliberately did not
# import from the reference fence, in BOTH directions: the fix must not also blind the rule.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
cd "$ROOT" || { printf 'cannot cd to repo root\n'; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ✓ %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  ✗ %s\n     %s\n' "$1" "${2:-}"; }

printf '\n== portable shell drills (the fence must be able to fail) ==\n'

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/portable-shell-drills.XXXXXX")" || SCRATCH=""
if [ -z "$SCRATCH" ] || [ ! -d "$SCRATCH" ]; then
  bad "could not create a scratch directory under ${TMPDIR:-/tmp} — cannot verify, which is not clean"
  printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
  exit 1
fi
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/yamlmirror" || { bad "could not create $SCRATCH/yamlmirror — cannot verify"; printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"; exit 1; }

# shellcheck source=frameworks/gates/lib/portable-shell-scan.sh
. "$ROOT/frameworks/gates/lib/portable-shell-scan.sh"

# drill <fixture-path> <rules> -> prints the finding count; leaves findings in $SCRATCH/drill-findings
# `grep -c` PRINTS 0 and EXITS 1 on no-match, so `grep -c … || printf 0` emits "0\n0" and every
# downstream `[ … -eq … ]` dies with "integer expression expected" — which is how a drill reports a
# failure it did not have. Capture, then default the empty case only.
drill() {
  printf '%s\n' "$1" > "$SCRATCH/drill-files"
  scan "$SCRATCH/drill-files" "$SCRATCH/drill-findings" "$2"
  drill_n="$(grep -c . "$SCRATCH/drill-findings" 2>/dev/null || true)"
  printf '%s\n' "${drill_n:-0}"
}

# --- the .sh-side drills -------------------------------------------------------------------------
printf '#!/usr/bin/env bash\nsed -i "s/a/b/" f\n' > "$SCRATCH/trip.sh"
n_drill="$(drill "$SCRATCH/trip.sh" "$RULES_HOST$RULES_BASHVER")"
if [ "${n_drill:-0}" -eq 1 ]; then
  ok "the real scan trips exactly once on a known-bad fixture (it is looking, not merely silent)"
else
  bad "the real scan produced ${n_drill:-0} finding(s) on a known-bad fixture, expected 1 — the 0-finding result in the sweep is meaningless"
fi
# …and the mirror, or the rule would simply ban `sed`.
printf '#!/usr/bin/env bash\nsed -i.bak "s/a/b/" f && rm -f f.bak\n' > "$SCRATCH/clean.sh"
n_clean="$(drill "$SCRATCH/clean.sh" "$RULES_HOST$RULES_BASHVER")"
if [ "${n_clean:-0}" -ne 0 ]; then
  bad "the real scan flagged the PORTABLE form (${n_clean} finding(s)) — the rule is over-broad"
else
  ok "the portable \`sed -i.bak\` form is not flagged"
fi

# The COUNTERPART field, drilled in both directions — the whole design, and the reason this lint
# does not drown a clean tree in false positives for every guarded fallback chain it already writes.
# shellcheck disable=SC2016 # fixture TEXT: these must reach the file unexpanded, that is the point
printf '#!/usr/bin/env bash\nHERE="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")"\n' > "$SCRATCH/guarded.sh"
n_guarded="$(drill "$SCRATCH/guarded.sh" "$RULES_HOST$RULES_BASHVER")"
if [ "${n_guarded:-0}" -eq 0 ]; then
  ok "a GUARDED \`readlink -f … || echo\` chain is not flagged (the counterpart field works)"
else
  bad "the real scan flagged a guarded fallback chain (${n_guarded} finding(s)) — the counterpart field is not matching, and every chain in the tree is a false positive"
fi
# shellcheck disable=SC2016 # fixture TEXT, as above
printf '#!/usr/bin/env bash\nHERE="$(dirname "$(readlink -f "$0")")"\n' > "$SCRATCH/unguarded.sh"
n_unguarded="$(drill "$SCRATCH/unguarded.sh" "$RULES_HOST$RULES_BASHVER")"
if [ "${n_unguarded:-0}" -eq 1 ]; then
  ok "an UNGUARDED \`readlink -f\` IS flagged — the counterpart exempts a chain, not the spelling"
else
  bad "an unguarded \`readlink -f\` produced ${n_unguarded:-0} finding(s), expected 1 — the counterpart field is exempting everything"
fi

# The exemption pragma, drilled in both directions: a reasoned pragma suppresses exactly its own
# line, and a bare marker with no reason suppresses nothing.
printf '#!/usr/bin/env bash\nsed -i "s/a/b/" f  # portable-ok: fixture, documents why this line is host-safe\n' > "$SCRATCH/exempt.sh"
n_exempt="$(drill "$SCRATCH/exempt.sh" "$RULES_HOST$RULES_BASHVER")"
if [ "${n_exempt:-0}" -eq 0 ]; then
  ok "a reasoned \`# portable-ok: <reason>\` pragma suppresses the finding on its line"
else
  bad "a reasoned \`# portable-ok: <reason>\` pragma did NOT suppress its line (${n_exempt} finding(s))"
fi
printf '#!/usr/bin/env bash\nsed -i "s/a/b/" f  # portable-ok:\n' > "$SCRATCH/bare.sh"
n_bare="$(drill "$SCRATCH/bare.sh" "$RULES_HOST$RULES_BASHVER")"
if [ "${n_bare:-0}" -eq 1 ]; then
  ok "a bare \`# portable-ok:\` with no reason does NOT suppress — the reason is enforced, not requested"
else
  bad "a bare \`# portable-ok:\` with no reason produced ${n_bare:-0} finding(s), expected 1 — exemptions can be added silently"
fi

# A COMMENT that discusses a banned spelling is not a defect. This tree's shell is heavily
# commented and several files — including this fence's own callers — name these constructs in
# prose. Without the comment arm the fence trips on its own documentation. Indented, because that
# is the shape the arm actually has to handle (it strips leading whitespace first).
printf '#!/usr/bin/env bash\nf() {\n  # declare -A is bash 4+, which is why this function does not use it\n  echo hi\n}\n' > "$SCRATCH/comment.sh"
n_comment="$(drill "$SCRATCH/comment.sh" "$RULES_HOST$RULES_BASHVER")"
if [ "${n_comment:-0}" -eq 0 ]; then
  ok "an INDENTED comment discussing \`declare -A\` is not flagged — the comment arm survived the port"
else
  bad "a comment discussing \`declare -A\` was flagged (${n_comment} finding(s)) — the fence trips on its own documentation"
fi

# --- the YAML-coverage drills --------------------------------------------------------------------

# (a) EXTRACTION WORKS, and line numbers survive it: a `run: |` block buries a bad spelling. If the
# reported location were the mirror's or raw extract's line rather than the ORIGINAL's, this would
# still "pass" with the wrong number — so the assertion checks the number, not just the count.
cat > "$SCRATCH/drillA.yml" <<'YAMLEOF'
jobs:
  build:
    steps:
      - run: |
          mapfile -t X < <(echo hi)
YAMLEOF
build_mirror "$SCRATCH/drillA.yml" "$SCRATCH/drillA.mirror"
n_drillA="$(drill "$SCRATCH/drillA.mirror" "$RULES_BASHVER")"
drillA_loc="$(head -n1 "$SCRATCH/drill-findings" 2>/dev/null | cut -d'@' -f1)"
drillA_line="${drillA_loc##*:}"
real_line="$(grep -n 'mapfile -t X' "$SCRATCH/drillA.yml" | cut -d: -f1)"
if [ "${n_drillA:-0}" -eq 1 ] && [ "$drillA_line" = "$real_line" ]; then
  ok "YAML extraction finds the buried \`mapfile\` exactly once, at the fixture's real line $real_line"
else
  bad "YAML extraction produced ${n_drillA:-0} finding(s) at line '${drillA_line:-<none>}', expected 1 finding at line $real_line — line numbers did not survive extraction"
fi

# (b) EXTRACTION IS NOT JUST GREP: the same word appears OUTSIDE any run: body (a `name:` value, a
# `#` comment). A lazy implementation that greps the whole YAML file would pass drill (a) too.
cat > "$SCRATCH/drillB.yml" <<'YAMLEOF'
name: mapfile is mentioned here, not inside a run block
jobs:
  build:
    steps:
      # a comment discussing mapfile, also not inside a run block
      - run: echo hi
YAMLEOF
build_mirror "$SCRATCH/drillB.yml" "$SCRATCH/drillB.mirror"
n_drillB="$(drill "$SCRATCH/drillB.mirror" "$RULES_BASHVER")"
if [ "${n_drillB:-0}" -eq 0 ]; then
  ok "\`mapfile\` outside any run: body (a name: value, a comment) is not flagged — extraction is structural, not textual"
else
  bad "extraction flagged ${n_drillB} finding(s) for \`mapfile\` text that sits outside every run: body — this is grep-the-whole-file wearing an extractor's name"
fi

# (c) THE SCOPE SPLIT IS REAL: RULES_HOST matches an unsuffixed `sed -i` unconditionally (no
# counterpart) — scope is enforced by never handing RULES_HOST a YAML mirror (the real sweep scans
# `.sh` files only). RULES_BASHVER is what actually scans every YAML mirror in production, so the
# meaningful drill is: this `sed -i` fixture, scanned with RULES_BASHVER, must be 0 — proving it has
# not absorbed a GNU/BSD rule. If the two tables were ever merged, this flips to 1.
cat > "$SCRATCH/drillC.yml" <<'YAMLEOF'
jobs:
  build:
    steps:
      - run: |
          sed -i "s/a/b/" f
YAMLEOF
build_mirror "$SCRATCH/drillC.yml" "$SCRATCH/drillC.mirror"
n_drillC="$(drill "$SCRATCH/drillC.mirror" "$RULES_BASHVER")"
if [ "${n_drillC:-0}" -eq 0 ]; then
  ok "an unsuffixed \`sed -i\` inside a run: block is not flagged by RULES_BASHVER — the GNU/BSD rules stay out of the table YAML is actually scanned with"
else
  bad "RULES_BASHVER flagged a run: block (${n_drillC} finding(s)) — the .sh-only scope for GNU/BSD rules has been merged away"
fi

# (d) THE RULES THAT MATTER HERE BITE: `shopt -s globstar`, then `${VAR,,}`.
printf '#!/usr/bin/env bash\nshopt -s globstar\necho **/*.txt\n' > "$SCRATCH/globstar.sh"
n_globstar="$(drill "$SCRATCH/globstar.sh" "$RULES_BASHVER")"
if [ "${n_globstar:-0}" -eq 1 ]; then
  ok "\`shopt -s globstar\` in a .sh fixture is flagged exactly once"
else
  bad "\`shopt -s globstar\` produced ${n_globstar:-0} finding(s), expected 1"
fi
printf '#!/usr/bin/env bash\necho "${MYVAR,,}"\n' > "$SCRATCH/caseconv.sh"
n_caseconv="$(drill "$SCRATCH/caseconv.sh" "$RULES_BASHVER")"
if [ "${n_caseconv:-0}" -eq 1 ]; then
  ok "\${MYVAR,,} case conversion is flagged exactly once"
else
  bad "\${MYVAR,,} produced ${n_caseconv:-0} finding(s), expected 1 — a rule in the fail-open class is inert"
fi

# (e) `declare -A` drilled directly: this is the construct live in
# frameworks/workflow-engines/engine/escalation-handler.sh today, and the reason Group B of the
# baseline is not empty.
printf '#!/usr/bin/env bash\nset -u\ndeclare -A ROUTES\nROUTES[a]=b\n' > "$SCRATCH/assoc.sh"
n_assoc="$(drill "$SCRATCH/assoc.sh" "$RULES_BASHVER")"
if [ "${n_assoc:-0}" -eq 1 ]; then
  ok "\`declare -A\` (the escalation-handler construct) is flagged exactly once"
else
  bad "\`declare -A\` produced ${n_assoc:-0} finding(s), expected 1 — a rule in the same fail-open class is inert"
fi

# --- the two NOT-IMPORTED false positives, drilled in both directions -----------------------------

# (f) FALSE POSITIVE 1, FIXED: the guarded idiom with the fallback on the NEXT line. This fixture is
# scripts/check-claude-config.sh's real `resolve_physical` shape. The reference fence flags it; a
# block-scoped counterpart does not. If this drill ever goes red, the port has re-imported the bug
# and the fence's only GNU/BSD finding would be the one file already doing it right.
# shellcheck disable=SC2016 # fixture TEXT, must reach the file unexpanded
printf '#!/usr/bin/env bash\nresolve_physical() {\n  local r\n  if r="$(readlink -f -- "$1" 2>/dev/null)" && [ -n "$r" ]; then printf %%s "$r"; return 0; fi\n  python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null\n}\n' > "$SCRATCH/nextline.sh"
n_nextline="$(drill "$SCRATCH/nextline.sh" "$RULES_HOST")"
if [ "${n_nextline:-0}" -eq 0 ]; then
  ok "a \`readlink -f\` guarded by a realpath fallback on the NEXT line is not flagged — false positive 1 was not imported"
else
  bad "the block-scoped counterpart did not match a next-line fallback (${n_nextline} finding(s)) — false positive 1 has been re-imported and the tree's one correct site is the fence's only finding"
fi

# (g) …and the BOUND on it. A `realpath` in an unrelated statement group, separated by blank lines,
# must NOT exempt anything: without this the widened guard degenerates into "the word appears
# somewhere in the file" and the rule becomes a decoration.
# shellcheck disable=SC2016 # fixture TEXT, must reach the file unexpanded
printf '#!/usr/bin/env bash\nHERE="$(dirname "$(readlink -f "$0")")"\n\nother() {\n  realpath /tmp\n}\n' > "$SCRATCH/farguard.sh"
n_farguard="$(drill "$SCRATCH/farguard.sh" "$RULES_HOST")"
if [ "${n_farguard:-0}" -eq 1 ]; then
  ok "a \`realpath\` in a DIFFERENT statement group does not exempt an unguarded \`readlink -f\` — the block window is bounded"
else
  bad "a distant \`realpath\` suppressed the finding (${n_farguard:-0} finding(s), expected 1) — the widened guard is now 'appears anywhere in the file'"
fi

# (h) FALSE POSITIVE 2, FIXED: a `mapfile` token inside awk's single-quoted PATTERN argument is not
# a call. The reference fence flags it.
printf "#!/usr/bin/env bash\nawk '/mapfile -t /{print FILENAME}' ./*.sh\n" > "$SCRATCH/awkpat.sh"
n_awkpat="$(drill "$SCRATCH/awkpat.sh" "$RULES_BASHVER")"
if [ "${n_awkpat:-0}" -eq 0 ]; then
  ok "a \`mapfile\` token inside awk's quoted pattern is not flagged — false positive 2 was not imported"
else
  bad "a quoted awk pattern containing \`mapfile\` was flagged (${n_awkpat} finding(s)) — false positive 2 has been re-imported"
fi

# (i) …and the NARROWNESS of it. `bash -c '<shell>'` is a real invocation and `bash` is deliberately
# absent from the pattern-command list, so its quoted argument is still scanned. Without this drill
# the masking could be widened to every quoted string and blind the rule wholesale.
printf "#!/usr/bin/env bash\nbash -c 'mapfile -t X < f'\n" > "$SCRATCH/bashc.sh"
n_bashc="$(drill "$SCRATCH/bashc.sh" "$RULES_BASHVER")"
if [ "${n_bashc:-0}" -eq 1 ]; then
  ok "\`bash -c 'mapfile …'\` IS still flagged — the quoted-pattern skip is scoped to pattern-taking commands, not all quotes"
else
  bad "\`bash -c 'mapfile …'\` produced ${n_bashc:-0} finding(s), expected 1 — the quoted-pattern skip has blinded the rule for every single-quoted string"
fi

printf '\n  %d passed, %d failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
