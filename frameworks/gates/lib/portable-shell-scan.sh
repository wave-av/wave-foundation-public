#!/usr/bin/env bash
# frameworks/gates/lib/portable-shell-scan.sh
# The SCAN ENGINE behind this repo's bash-3.2 / GNU-vs-BSD portability fence. This file defines the
# rules tables, `scan()`, the YAML `run:` extractor, and the file-list builders — nothing else. It is
# a LIBRARY, not a program: `frameworks/gates/test-portable-shell.sh` sources it to run the real
# sweep over the tree, and `frameworks/gates/test-portable-shell-drills.sh` sources it to drill the
# rules against fixtures. See either caller's own header for the WHY of the fence itself; this file
# is the HOW.
#
# PORTED from the sibling private repo's fence. The scan semantics are carried over; the file-list
# builders are scoped to where THIS repo's shell actually lives, and TWO rule-engine defects that
# the reference ships were deliberately NOT imported — see "TWO FALSE POSITIVES NOT IMPORTED" below.
#
# CRITICAL DESIGN INVARIANT: the drills MUST source this exact file and call its real `scan()` and
# `build_mirror()` — never a copy. A drill only proves something if it exercises the SAME code path
# the sweep runs; a drills file that pasted its own scan loop would keep passing even if this
# file's `scan()` were deleted.
#
# MAIN-GUARD: a library that can be executed as if it were the program it supports exits 0 having
# done nothing — a silent guard. `.github/workflows/self-check.yml` discovers suites with
# `git ls-files 'frameworks/gates/test-*.sh'`; that glob does not match this path, which is why the
# lib lives here (`frameworks/gates/lib/workflow-policy-harness.sh` is the precedent). The guard
# below makes the intent explicit rather than leaving it to the glob.
case "${0##*/}" in
  portable-shell-scan.sh)
    printf 'portable-shell-scan.sh is a LIBRARY — source it from a test-*.sh suite, do not execute it\n' >&2
    exit 2
    ;;
esac

# ── TWO FALSE POSITIVES NOT IMPORTED ──────────────────────────────────────────────────────────
#
# (1) THE LINE-SCOPED `readlink -f` GUARD. The reference decides "is this guarded?" by looking for
#     a fallback arm ON THE SAME LINE. The guarded idiom this tree actually writes puts the fallback
#     on the NEXT line — an `if r="$(readlink -f -- "$1" 2>/dev/null)" && [ -n "$r" ]; then …; fi`
#     followed by a `python3` realpath fallback (scripts/check-claude-config.sh). That is CORRECT
#     code — the one site in this repo already doing the right thing — and a line-scoped rule flags
#     it. A fence whose sole GNU/BSD finding is the file that got it right teaches every reader to
#     ignore the rule. So the guard here carries a SCOPE field: `line` (the reference's behaviour,
#     kept where it is right) or `block`, which searches the enclosing statement group. See
#     `_PSL_WINDOW_AWK` for what "enclosing" means and for the bound on it.
#
# (2) A CONSTRUCT MATCHED INSIDE A QUOTED REGEX/PATTERN ARGUMENT. A `mapfile` token inside an
#     `awk '/mapfile/ {…}'` program text is a PATTERN, not a call — flagging it is a category error,
#     and this tree greps for shell spellings in several places (this very fence does). `scan()`
#     therefore re-tests every candidate against a copy of the line with single-quoted segments
#     blanked, but ONLY when the line invokes a known pattern-taking command; if the rule stops
#     matching once the pattern text is removed, the match lived entirely inside the pattern and is
#     dropped. The narrowness is deliberate: `bash -c 'mapfile …'` is a real call and `bash` is not
#     on the list, so it stays flagged.
#
# ── RULES TABLES ──────────────────────────────────────────────────────────────────────────────
#
# FORMAT, `@@`-delimited, FIVE fields:
#     <extended-regex>@@<counterpart-regex>@@<guard-scope>@@<why>@@<portable-fix>
#
# The COUNTERPART field is why this lint does not drown a clean tree in noise. Banning `readlink -f`
# or `date -d` outright flags every guarded fallback chain in the tree — all false positives,
# because the portable idiom IS a guarded chain (`readlink -f "$0" 2>/dev/null || echo "$0"`,
# `date -v-2H … || date -d '2 hours ago'`). The defect is never the spelling — it is an UNGUARDED
# spelling. So a hit counts only when the counterpart is ABSENT from the guard scope, and the
# counterpart must match the actual FALLBACK ARM, not the mere presence of `||`: `readlink -f …
# || exit 1` still breaks on macOS and is still flagged. An empty counterpart means "always flag",
# for cases where no fallback makes sense (there is no sensible `sed -i` fallback).
#
# GUARD SCOPE is `line` or `block`. `block` is used for the two rules whose portable form is a
# multi-line fallback chain (`readlink -f`, `date -d`); every other rule has an empty counterpart,
# so its scope is inert and recorded as `line`.
#
# Static literals — nothing is built from repo content, so there is no dynamic-regex surface, and
# no path is interpolated into a shell string or eval'd.
#
# RULES_HOST — the GNU/BSD rules. These are only correct to flag on code that runs on an operator's
# macOS host (BSD userland); a `run:` step is correct to use GNU spellings because it runs on the
# ubuntu runner BY DESIGN, so callers scan this table over `.sh` sources only.
# shellcheck disable=SC2034 # consumed by the files that source this lib, not this file itself
RULES_HOST="
sed -i[^.]@@@@line@@\`sed -i\` with no suffix is GNU-only; BSD sed reads the next word as the backup extension@@sed -i.bak … && rm -f ….bak  —or—  sed … > tmp && mv tmp file
readlink -f@@\\|\\| *(echo|printf)|realpath@@block@@\`readlink -f\` is GNU-only and macOS lacks it without coreutils, with no portable fallback arm in the enclosing block@@if r=\"\$(readlink -f -- \"\$1\" 2>/dev/null)\" && [ -n \"\$r\" ]; then …; fi  + a realpath fallback
date -d @@date -v@@block@@\`date -d\` is GNU and BSD date uses -v, with no BSD arm in the enclosing block@@date -v-2H … 2>/dev/null || date -d '2 hours ago' …
grep -P@@@@line@@\`grep -P\` (PCRE) is not compiled into BSD grep@@grep -E with a POSIX ERE
base64 -w@@@@line@@\`base64 -w\` is GNU; BSD base64 has no wrap flag@@base64 piped through tr -d
cp --parents@@@@line@@\`cp --parents\` is GNU-only@@mkdir -p \"\$(dirname \"\$dst\")\" && cp \"\$src\" \"\$dst\"
find .* -printf@@@@line@@\`find -printf\` is GNU-only@@find … -exec printf … {} +
"

# RULES_BASHVER — bash-VERSION constructs. Unlike the GNU/BSD rules, these are wrong wherever the
# body actually runs on `/bin/bash` 3.2.57, which includes YAML `run:` bodies: an operator running a
# gate body locally, or any of this repo's `.sh` gates invoked from a macOS shell, hits 3.2.
# Callers scan this table over BOTH `.sh` sources and the extracted YAML `run:` text.
#
# The class is "bash-4-only construct that fails SILENTLY and leaves rc 0". `declare -A` on 3.2
# makes an ordinary indexed array and every keyed write collapses onto index 0, so a lookup table
# answers with one value; `shopt -s globstar` prints "invalid shell option name" and KEEPS GOING
# with rc 0, so `**` degrades to a single `*`; `${VAR,,}` is a parse error that, absent `set -e`,
# leaves the variable empty so no branch matches and the script reaches an implicit exit 0.
# `mapfile` is rc 127, which fails loud only where the caller checks. A gate written with any of
# them reads green forever.
# shellcheck disable=SC2034 # consumed by the files that source this lib, not this file itself
RULES_BASHVER="
(mapfile|readarray) @@@@line@@\`mapfile\`/\`readarray\` are bash 4+; /bin/bash on macOS is 3.2.57@@redirect into a temp file and read it with a while-read loop
(declare|local)[[:space:]]+-A@@@@line@@\`declare -A\`/\`local -A\` (associative arrays) are bash 4+; /bin/bash on macOS is 3.2.57, with no portable equivalent@@parallel indexed arrays with a lookup helper, a delimited string keyed via case/grep, or a \`# portable-ok:\` pragma if the script is proven not host-run
shopt +-s +globstar@@@@line@@\`shopt -s globstar\` is bash 4+; on 3.2 it prints \"invalid shell option name\" and KEEPS GOING with rc 0, so \`**\` silently degrades to a single \`*\`@@a bare directory argument, or an explicit find/while-read walk
\\\$\\{[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?[,^]@@@@line@@\`\${VAR,,}\` / \`\${VAR^^}\` case conversion is bash 4+; on 3.2 it errors and KEEPS GOING, leaving the variable empty so no branch matches and the script reaches an implicit exit 0@@printf '%s' \"\$x\" | tr '[:upper:]' '[:lower:]'
"

# --- the block-scoped guard window ------------------------------------------------------------
#
# What "the enclosing block" means, stated precisely so the exemption it grants is auditable: the
# contiguous run of NON-BLANK lines containing the hit, bounded to `win` lines either side. In shell
# as written here, a blank line separates statement groups, so that run IS the enclosing function
# body / `if`…`fi` / `&&`…`||` chain, plus the comment block above it where a fallback is often
# EXPLAINED as well as written.
#
# THE BOUND IS THE POINT. Without it one `realpath` anywhere in a 600-line file would exempt every
# `readlink -f` in it and the rule would be a decoration. 12 lines either side covers a function
# body and its header comment and no more; a fallback further away than that is not one a reader
# can see. Drills (f) and (g) pin BOTH directions of this bound.
_PSL_WINDOW_AWK='
{ L[NR] = $0 }
END {
  lo = target
  while (lo > 1 && L[lo-1] ~ /[^ \t]/ && target - (lo-1) <= win) lo--
  hi = target
  while (hi < NR && L[hi+1] ~ /[^ \t]/ && (hi+1) - target <= win) hi++
  for (i = lo; i <= hi; i++) print L[i]
}
'
_PSL_WINDOW_LINES=12

# psl_guard_window <file> <line-number>: prints the guard window described above.
psl_guard_window() {
  awk -v target="$2" -v win="$_PSL_WINDOW_LINES" "$_PSL_WINDOW_AWK" "$1" 2>/dev/null
}

# --- quoted-pattern masking --------------------------------------------------------------------
#
# Commands whose arguments are REGEXES OR PROGRAM TEXT, not shell. A construct spelled inside a
# single-quoted argument to one of these is a pattern, not a call. Kept deliberately short: every
# name added here is a place the fence stops looking, and `bash -c '…'`, `sh -c '…'`, `eval` and
# `xargs` are absent ON PURPOSE because their quoted argument IS shell that really runs.
_PSL_PATTERN_CMDS='(^|[[:space:];(|&])(awk|gawk|nawk|grep|egrep|fgrep|sed|perl|rg|ack)([[:space:]]|$)'

# psl_mask_quoted_patterns <line-body>: prints the body with every single-quoted segment blanked,
# but only if the body invokes one of the commands above; otherwise prints the body unchanged.
psl_mask_quoted_patterns() {
  if printf '%s' "$1" | grep -qE "$_PSL_PATTERN_CMDS"; then
    printf '%s' "$1" | sed "s/'[^']*'/''/g"
  else
    printf '%s' "$1"
  fi
}

# --- scan() ------------------------------------------------------------------------------------
#
# A line may opt out with `# portable-ok: <reason>`. The marker must sit in a trailing comment and
# be followed by non-whitespace text — a REASON is required, so an exemption cannot be added
# silently.
#
# scan <files-list-file> <findings-out-file> <rules-table>
# Runs every rule in the given table over every file listed (one path per line) and writes one line
# per finding to the out file, `@@`-delimited: <file>:<line>@@<why>@@<fix>. Findings are DATA, not
# verdicts: the caller decides whether a finding is a failure (the real sweep) or the expected
# result (the fixture drill). Scan ERRORS — grep exit >1, i.e. an invalid ERE or an unreadable file
# — call `bad()` directly (a function the CALLER must define): "could not check" must never
# collapse into "nothing wrong found". Requires `$SCRATCH` to be a writable scratch directory.
# Taking the rules table as an explicit argument (rather than one global `$RULES`) is what lets the
# sweep run the host rules over `.sh` only and the bash-version rules over `.sh` AND YAML mirrors,
# while a drill asks for exactly the rules it means to exercise.
scan() {
  scan_list="$1"; scan_out="$2"; scan_rules="$3"
  : > "$scan_out"
  scan_errors=0
  while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    re="${rule%%@@*}";      rest="${rule#*@@}"
    guard="${rest%%@@*}";   rest="${rest#*@@}"
    scope="${rest%%@@*}";   rest="${rest#*@@}"
    why="${rest%%@@*}";     fix="${rest##*@@}"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # NOT `|| true`, and NOT 2>/dev/null: grep exit 1 is "no match" (fine), exit >1 is "could not
      # search" (invalid ERE, unreadable file). Swallowing the latter would leave a broken rule
      # permanently inert while the suite still prints the reassuring 0-findings line.
      grep -nE "$re" "$f" > "$SCRATCH/matches" 2> "$SCRATCH/grep-err"
      st=$?
      if [ "$st" -gt 1 ]; then
        scan_errors=$((scan_errors+1))
        bad "rule \`$re\` could not be checked against $f (grep exit $st) — unverified is not clean" \
            "$(cat "$SCRATCH/grep-err" 2>/dev/null)"
        continue
      fi
      # Comment lines are skipped: this repo's shell is heavily commented and several files
      # legitimately DISCUSS these spellings in prose — including this fence's own callers. Without
      # this arm, the lint trips on its own documentation. Leading whitespace is stripped first, so
      # an INDENTED comment is skipped too.
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        n="${line%%:*}"; body="${line#*:}"
        first="$(printf '%s' "$body" | sed 's/^[[:space:]]*//' | cut -c1)"
        [ "$first" = "#" ] && continue
        # The exemption must be a trailing `#` comment AND carry non-whitespace after the colon:
        # a bare `portable-ok:` with no reason does not suppress anything.
        case "$body" in *"# portable-ok:"*[![:space:]]*) continue ;; esac
        # FALSE POSITIVE (2): if the rule stops matching once single-quoted pattern arguments are
        # blanked, the match lived entirely inside a regex/program text and is not a call.
        if ! printf '%s' "$(psl_mask_quoted_patterns "$body")" | grep -qE "$re"; then continue; fi
        # FALSE POSITIVE (1): counterpart present in the guard SCOPE => the portable guarded idiom.
        if [ -n "$guard" ]; then
          if [ "$scope" = "block" ]; then
            guard_text="$(psl_guard_window "$f" "$n")"
          else
            guard_text="$body"
          fi
          if printf '%s' "$guard_text" | grep -qE "$guard"; then continue; fi
        fi
        printf '%s@@%s@@%s\n' "$f:$n" "$why" "$fix" >> "$scan_out"
      done < "$SCRATCH/matches"
    done < "$scan_list"
  done <<EOF
$scan_rules
EOF
}

# --- YAML extraction: a sparse mirror per file, so LINE NUMBERS STAY REAL ----------------------
#
# scan() reports the line number grep gives it. Squashing every `run:` body into one buffer per file
# would report the buffer's line, not the YAML file's. Instead, for each tracked YAML file we build
# a MIRROR under `$SCRATCH/yamlmirror/<original/path>` where mirror line N holds original line N's
# content if that line sits inside a `run:` body (or is the inline scalar following `run:`), and is
# BLANK otherwise. scan() runs unmodified over the mirror and reports a line number correct for both
# it and the original it shadows; the caller strips the `$SCRATCH/yamlmirror/` prefix so a finding
# names the real path, not a temp file.
#
# The blank-outside-run: property also makes the block-scoped guard window behave correctly on a
# mirror: a `run:` body is bounded by blanks, so the window cannot wander into another step.
#
# The extractor is a single-pass awk program tracking whether we are inside a `run:` block by
# indentation (the only structural signal YAML gives here), emitting lines until one is indented no
# deeper than the `run:` key. It emits `<origline>:` for blank lines inside the block and
# `<origline>:<content>` otherwise; lines it never emits (outside any run body) are filled blank by
# the merge step below.
_PSL_EXTRACT_AWK='
function indent_of(s,   i, n) { n = 0; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c == " ") n++; else if (c == "\t") n += 8; else break } return n }
{
  line = $0
  if (inblock) {
    if (line ~ /^[[:space:]]*$/) { print NR ":"; next }
    if (indent_of(line) > keyind) { print NR ":" line; next }
    inblock = 0
  }
  if (match(line, /^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*/)) {
    keyind = indent_of(line)
    rest = substr(line, RSTART + RLENGTH)
    sub(/[[:space:]]+$/, "", rest)
    if (rest ~ /^[|>][-+0-9]*$/ || rest == "") { inblock = 1; next }
    print NR ":" rest
  }
}
'

# build_mirror <original-yaml-path> <mirror-dest-path>: runs the extractor, then merges its sparse
# `N:content` output against the file's real line count so every original line number 1..total gets
# an entry (extracted content, or blank). The merge is itself plain awk — no mapfile, no bash arrays
# — because this file must stay bash-3.2 clean; it is scanned by its own suite. Requires the caller
# to have set `$SCRATCH`.
build_mirror() {
  bm_src="$1"; bm_dest="$2"
  mkdir -p "$(dirname "$bm_dest")" || return 1
  bm_total="$(awk 'END{print NR}' "$bm_src" 2>/dev/null)"
  bm_total="${bm_total:-0}"
  awk "$_PSL_EXTRACT_AWK" "$bm_src" > "$SCRATCH/extract.raw" 2>/dev/null || true
  awk -v total="$bm_total" '
    {
      colon = index($0, ":")
      ln = substr($0, 1, colon - 1) + 0
      arr[ln] = substr($0, colon + 1)
      seen[ln] = 1
    }
    END {
      for (i = 1; i <= total; i++) { if (seen[i]) print arr[i]; else print "" }
    }
  ' "$SCRATCH/extract.raw" > "$bm_dest"
}

# --- file-list builders ------------------------------------------------------------------------
#
# psl_build_sh_files <out-file>: every tracked shell source, minus the three files that ARE this
# fence (this lib, the sweep, the drills) — every occurrence of a rule spelling in those three is a
# pattern definition by construction, not a defect.
#
# THE SCOPE IS CENSUSED, NOT COPIED FROM THE REFERENCE. Measured against origin/main: 90 tracked
# `.sh` — 59 under `frameworks/`, 17 under `plugin/`, 14 under `scripts/`. The private reference
# additionally excludes `staging/**`; this repo has NO `staging/` tree (`git ls-files 'staging/*'`
# → 0), so that exclusion is dropped rather than carried in as dead configuration. All 90 files are
# gate- or hook-carrying code and all are in scope.
#
# `frameworks/gates/fixtures/**` IS excluded: DELIBERATELY MALFORMED inputs owned by other gates.
# Linting a fixture FOR correctness is how fixture-isolation defects start — its job is to be wrong.
#
# `git ls-files` means TRACKED files only, filtered via a pipeline into a file rather than
# `mapfile`, for the same bash-3.2 reason this whole fence exists. Prints the count to stdout.
psl_build_sh_files() {
  psl_out="$1"
  git ls-files '*.sh' \
    | grep -v '^frameworks/gates/fixtures/' \
    | grep -v '^frameworks/gates/test-portable-shell\.sh$' \
    | grep -v '^frameworks/gates/test-portable-shell-drills\.sh$' \
    | grep -v '^frameworks/gates/lib/portable-shell-scan\.sh$' > "$psl_out" || true
  psl_count "$psl_out"
}

# psl_count <file>: line count, 0 for empty. `grep -c` PRINTS 0 and EXITS 1 on no-match, so the
# obvious `grep -c … || printf '0\n'` emits "0\n0" and the caller's zero-guard dies with "integer
# expression expected" instead of reporting the empty scan set it exists to catch.
psl_count() {
  psl_n="$(grep -c . "$1" 2>/dev/null || true)"
  printf '%s\n' "${psl_n:-0}"
}

# psl_build_yaml_files <out-file>: tracked YAML on the same surface. Measured against origin/main:
# 59 tracked `.yml`/`.yaml`, of which 26 are `frameworks/gates/fixtures/**` and excluded for the
# reason above, leaving 33 in scope — 18 of them `.github/workflows/`. Prints the count to stdout.
psl_build_yaml_files() {
  psl_out="$1"
  git ls-files '*.yml' '*.yaml' \
    | grep -v '^frameworks/gates/fixtures/' > "$psl_out" || true
  psl_count "$psl_out"
}

# psl_build_yaml_mirrors <yaml-files-list> <mirror-list-out>: builds a sparse mirror (see
# build_mirror above) for every file in <yaml-files-list> under `$SCRATCH/yamlmirror/`, writes the
# resulting mirror paths to <mirror-list-out>, and prints the total non-blank extracted line count
# to stdout — the "did the extractor find anything at all" signal the caller's zero-guard needs.
psl_build_yaml_mirrors() {
  psl_yamlfiles="$1"; psl_mirrorlist="$2"
  : > "$psl_mirrorlist"
  psl_total_lines=0
  while IFS= read -r yf; do
    [ -n "$yf" ] || continue
    dest="$SCRATCH/yamlmirror/$yf"
    build_mirror "$yf" "$dest" || { bad "could not build a YAML mirror for $yf"; continue; }
    printf '%s\n' "$dest" >> "$psl_mirrorlist"
    this_lines="$(grep -c . "$dest" 2>/dev/null || true)"
    psl_total_lines=$((psl_total_lines + ${this_lines:-0}))
  done < "$psl_yamlfiles"
  printf '%s\n' "$psl_total_lines"
}
