#!/usr/bin/env bash
# secret-scan — the CANONICAL credential-shape gate for the WAVE fleet.
#
# THE POINT OF THIS FILE IS THAT THERE IS ONLY ONE OF IT. Before #926 the same gate existed four
# times across three files (checks.yml x2, self-check.yml, dogfood.sh), held in sync by a comment
# reading "must mirror self-check.yml" — a maintenance contract enforced by nobody. They had already
# drifted two ways: two copies omitted `--exclude-dir=dist`, and two failed OPEN on a missing
# allowlist. A gate that is copied is a gate that will disagree with itself.
#
# It follows the pattern the Claude-API gates already prove in this repo: a script CI runs and a
# human runs at commit time are the SAME FILE, so "it passed locally" and "it passed in CI" are the
# same claim rather than two claims that happen to agree.
#
# Usage:  bash frameworks/gates/secret-scan.sh [path]      (default: repo root, cwd)
# Exit:   0 = clean · 1 = credential-shaped string found outside the allowlist, a malformed
#         allowlist (#932), or a scan that could not run or could not write its temp files — all gate
#         failures, because a config file that cannot be parsed must never resolve to "no findings".
# Read-only: no network, no token. Environment inputs: GITHUB_EVENT_NAME, PR_BASE_SHA, PR_HEAD_SHA and
# MERGE_BASE_SHA select where exceptions are read from (see below). Unset, as at commit time, the
# working tree is used. A finding prints as file:line only, because the output is a CI log.
set -uo pipefail

ROOT="${1:-.}"
# Resolved against ROOT, not cwd. Read from cwd it would scan the tree you NAMED while applying the
# exceptions of the tree you happen to be STANDING IN — a gate reporting on ambient state instead of
# its argument. No behaviour change for the registered invocation (`pass_filenames: false` -> ROOT="."
# -> `./.github/...`); it only makes `secret-scan.sh <other-tree>` mean what it reads like.
ALLOWLIST="$ROOT/.github/.secret-allowlist"

# Real-secret shapes. Lines tagged `pragma: allowlist secret` are skipped, which is how a vetting
# module or a test fixture can define key SHAPES without tripping the gate that looks for them.
# `whsec_` takes a base64 tail (Svix issues those as well as Stripe's alphanumeric form). `wk_` is
# anchored so an identifier that merely ends in those letters is not a key.
PATTERNS='(sk-[A-Za-z0-9]{20}|sk_(live|test)_[A-Za-z0-9]{20}|npm_[A-Za-z0-9]{30}|sbp_[a-f0-9]{40}|github_pat_[A-Za-z0-9_]{40}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30}|AIzaSy[A-Za-z0-9_-]{20}|xai-[A-Za-z0-9]{40}|xoxb-[A-Za-z0-9-]+|whsec_[A-Za-z0-9+/]{20}|(^|[^A-Za-z0-9_])wk_(live_|test_)?[A-Za-z0-9.-]{20}|-----BEGIN [A-Z ]*PRIVATE KEY)'

# WHERE EXCEPTIONS COME FROM. On a pull request or merge queue run they are read from the BASE
# commit, the same rule the token-budget gate applies to its control files (#958): an exception
# takes effect once it is on the base branch, and removing one bites immediately: an entry holds only
# if it is on the base AND still in the tree, or a change removing one would pass here and fail on
# the base branch after it merged. Absent at base is EMPTY, never permission, and a run that cannot
# resolve its base has no exceptions. Any other run (push, a local commit) checks a tree nothing
# further will review, so the tree is the source.
#
# THE BASE OF GITHUB'S MERGE COMMIT. A pull request run checks out refs/pull/N/merge, the CURRENT base
# branch merged with the PR head, while PR_BASE_SHA can be older than that merge. A pragma line a peer
# merged in between is in the tree and not in the older commit, so a change that never touched that
# file would fail. The first parent is the base branch as merged, the same correction the token-budget
# gate makes (private-repo#1605). The second parent must EQUAL PR_HEAD_SHA, never just exist:
# an author merging the base into their own branch has the parents the other way round, and taking
# the first there would make the change its own base.
#
# THE FORK POINT OF A HEAD CHECKOUT. Buildkite checks out the head itself, with PR_BASE_SHA at the base
# branch's tip. A peer's edit there is not in the tree, so a line the change never touched differs
# from that tip and would fail. When HEAD equals PR_HEAD_SHA the base is the merge base of the two, the
# commit the token-budget gate diffs against. No merge base, as in a shallow clone, is no base: no
# exceptions and a warning. The token-budget gate falls back to the tip there, which would put back
# this failure and take exceptions from a commit the head never had.
base_mode=0
scan_base=""
case "${GITHUB_EVENT_NAME:-}" in
  pull_request|pull_request_target|merge_group) base_mode=1 ;;
esac
merged_base=""
if [ -n "${PR_HEAD_SHA:-}" ] && [ "$(git -C "$ROOT" rev-parse -q --verify 'HEAD^2' 2>/dev/null || true)" = "$PR_HEAD_SHA" ]; then
  merged_base=$(git -C "$ROOT" rev-parse -q --verify 'HEAD^1' 2>/dev/null || true)
fi
wanted_base="${merged_base:-${PR_BASE_SHA:-${MERGE_BASE_SHA:-}}}"
if [ -n "$wanted_base" ]; then
  base_mode=1
  scan_base=$(git -C "$ROOT" rev-parse --verify --quiet "$wanted_base^{commit}" 2>/dev/null) || scan_base=""
fi
if [ -n "$scan_base" ] && [ -n "${PR_BASE_SHA:-}" ] &&
  [ "$(git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null || true)" = "${PR_HEAD_SHA:-}" ]; then
  scan_base=$(git -C "$ROOT" merge-base HEAD "$scan_base" 2>/dev/null) || scan_base=""
fi

# The allowlist is an EXCEPTION list, so a MISSING one must mean "no exceptions" — never "no
# findings". The historical bug (#926) was `{ grep -vFf "$ALLOWLIST" || true; }`: with the file
# absent, grep errors, writes nothing to stdout, and `|| true` swallows the failure, leaving the
# result empty and passing ANY tree. Guarding on the file and falling through to `cat` fails CLOSED.
#
# `|| cat` is also safe in the case that LOOKS unsafe — the file exists and filters every line, so
# grep exits 1 and the `||` branch fires: grep has already drained stdin, so `cat` reads EOF and
# re-emits nothing. Verified on GNU grep 3.8 / x86_64 Linux against all three cases (allowlist
# absent -> detect · filters everything -> clean, no re-emit · present but non-matching -> detect).
# ⚠️ A BLANK LINE IN THE ALLOWLIST DISABLES THE ENTIRE SCANNER. `grep -F -f file` treats an empty
# line as the empty pattern, which matches EVERY input line, so `-v` then discards all findings and
# the gate passes any tree. Measured on GNU grep 3.8 (CI's binary) AND BSD grep 2.6 against the real
# committed .github/.secret-allowlist, which has one blank line: zero survivors. This is not a
# hypothetical — it silently disabled secret scanning in CI. Strip blank/whitespace-only lines (and
# `#` comments, which -F would otherwise match literally) before using the file as a pattern source.
# If every line is stripped the result is an empty pattern file, which excludes nothing — fail-closed.
#
# Every mktemp result is checked. This file runs without -e, so a failed one leaves an empty name: no
# redirect opens, grep never runs, and a tree nothing scanned would report clean.
#
# So is every write to a temp file, because a hit that never reached its file reads the same as no
# hit. A grep writes through `| cat`, because a redirect it cannot open and its own "no match" are
# both exit 1, and cat's status is only about the write.
allow_patterns="" allow_source="" raw_hits="" scan_errors="" base_copy="" findings=""
trap 'rm -f "$allow_patterns" "$allow_source" "$raw_hits" "$scan_errors" "$base_copy" "$findings"' EXIT
if ! { allow_patterns=$(mktemp) && allow_source=$(mktemp) && raw_hits=$(mktemp) &&
  scan_errors=$(mktemp) && base_copy=$(mktemp) && findings=$(mktemp); }; then
  echo "::error::secret-scan: could not create a temp file, refusing to report clean"
  exit 1
fi
write_failed() {
  echo "::error::secret-scan: could not write a temp file, refusing to report clean"
  exit 1
}
# copy_from_base <spec> <file>: absent at base is an empty file. Asking first keeps "absent" apart from
# a write that failed, which git show would report the same way.
copy_from_base() {
  if git -C "$ROOT" cat-file -e "$1" 2>/dev/null; then
    git -C "$ROOT" show "$1" > "$2" 2>/dev/null || write_failed
  else
    : > "$2" || write_failed
  fi
}
if [ "$base_mode" -eq 0 ]; then
  if [ -f "$ALLOWLIST" ] && [ -r "$ALLOWLIST" ]; then
    cat "$ALLOWLIST" > "$allow_source" 2>/dev/null || write_failed
  fi
elif [ -n "$scan_base" ]; then
  # -x compares whole lines, so a blank line in the tree's copy keeps nothing but blank lines.
  copy_from_base "$scan_base:./.github/.secret-allowlist" "$base_copy"
  if [ -f "$ALLOWLIST" ] && [ -r "$ALLOWLIST" ]; then
    grep -Fxf "$ALLOWLIST" "$base_copy" | cat > "$allow_source"
    [ "${PIPESTATUS[1]}" -eq 0 ] || write_failed
  else
    : > "$allow_source" || write_failed
  fi
else
  echo "::warning::secret-scan: this change has no base commit available, so no exceptions apply"
fi
grep -vE '^[[:space:]]*($|#)' "$allow_source" | cat > "$allow_patterns"
[ "${PIPESTATUS[1]}" -eq 0 ] || write_failed

# ── #932: the allowlist validates BEFORE it filters ──────────────────────────────────────────────
# Sanitizing (above) stops the blank line from disabling the scanner. It does not stop the NEXT
# malformed input, and it does so silently — the author keeps a file they believe grants exceptions
# while it quietly grants none, or grants far more than they think. The rule this encodes:
#
#     an exception list that fails to parse must mean "NO EXCEPTIONS", never "no findings".
#
# So every defect below is a hard gate failure with a named reason, never a warning that scrolls by.
# Errors report the LINE NUMBER and the reason, never the line's content: the allowlist enumerates
# credential shapes, and the failure path is a CI log.
validate_allowlist() {
  [ -f "$ALLOWLIST" ] || return 0
  local n=0 entries=0 bad=0 line stripped
  # `|| [ -n "$line" ]` so a final line with no trailing newline is still read, not silently dropped
  # — the exact place a defect would hide from a validator that trusts read's exit status alone.
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    # Classify blank vs comment with the sanitizer's EXACT regex. If the validator and the filter
    # disagree about what counts as a pattern, the validator blesses a file the filter reads
    # differently — which is this entire bug class, one layer up.
    if printf '%s\n' "$line" | grep -qE '^[[:space:]]*$'; then
      echo "::error::$ALLOWLIST:$n: blank or whitespace-only line — \`grep -F\` reads it as the empty pattern, which matches every line and disables the scan"
      bad=1; continue
    fi
    # A comment is legitimate — the sanitizer strips it, so it never becomes a pattern.
    printf '%s\n' "$line" | grep -qE '^[[:space:]]*#' && continue
    entries=$((entries + 1))

    # Trailing whitespace / CR (a CRLF checkout) makes the entry a fixed string that can never match
    # any scan line — a DEAD exception the author believes is live. Opposite direction to the blank
    # line, same root defect: what the file says and what grep does have come apart.
    case "$line" in
      *[[:space:]]|*$'\r')
        echo "::error::$ALLOWLIST:$n: trailing whitespace or CR — as a FIXED string this entry can never match, so the exception is dead"
        bad=1; continue ;;
    esac

    stripped="$line"
    # Glob/regex metacharacters are LITERALS under -F. An author writing `staging/*.md` gets an entry
    # matching the seven characters `staging/*.md` and nothing else — silently no exception at all.
    case "$stripped" in
      *'*'*|*'?'*|*'['*)
        echo "::error::$ALLOWLIST:$n: contains a glob metacharacter — entries are FIXED strings (\`grep -F\`), so \`*\`/\`?\`/\`[\` match literally and grant no exception"
        bad=1; continue ;;
    esac
    # A bare `.` or `/` is a substring of essentially every path, so it allowlists the whole tree.
    case "$stripped" in
      .|..|/|./)
        echo "::error::$ALLOWLIST:$n: a bare path element matches nearly every scanned line — this allowlists the entire tree"
        bad=1; continue ;;
    esac
    # Same hazard, quantified: a fixed substring under 3 chars is too broad to be a real exception.
    if [ "${#stripped}" -lt 3 ]; then
      echo "::error::$ALLOWLIST:$n: entry is shorter than 3 characters — as a fixed SUBSTRING it is far too broad to be a deliberate exception"
      bad=1; continue
    fi
  done < "$ALLOWLIST"

  # Every line was a comment or blank: the author holds a non-empty exception file granting nothing.
  # That is survivable (it fails CLOSED) but it is never what anyone intended, so say it out loud.
  if [ "$n" -gt 0 ] && [ "$entries" -eq 0 ]; then
    echo "::error::$ALLOWLIST: has $n line(s) but sanitizes to ZERO patterns — every line is a comment or blank, so this file grants no exceptions at all"
    bad=1
  fi

  [ "$bad" -eq 0 ] || {
    echo "::error::$ALLOWLIST is malformed — refusing to scan. A malformed exception list means NO exceptions, never 'no findings'."
    exit 1
  }
}
validate_allowlist

# Advisory only (never changes the exit code): an entry naming a path that no longer exists is a
# standing exception nobody is reviewing. It is not a correctness defect — a stale entry grants an
# exception to nothing — so it must not fail a build that is otherwise clean.
if [ -s "$allow_patterns" ]; then
  while IFS= read -r entry; do
    case "$entry" in
      # `..` is skipped rather than resolved: the entry is attacker-influenceable via a PR, and a
      # traversal would have this check stat paths outside the tree being scanned. It is only ever
      # tested with `[ -e ]` — never expanded, evaluated or word-split.
      *..*) ;;
      */*)
        # A path:line entry names the path before its line number.
        listed="${entry%:}"
        case "${listed##*:}" in
          ''|*[!0-9]*) listed="$entry" ;;
          *) listed="${listed%:*}" ;;
        esac
        [ -e "$ROOT/$entry" ] || [ -e "$ROOT/$listed" ] ||
          echo "note: $ALLOWLIST: '$entry' matches no path under $ROOT — stale exception?" ;;
    esac
  done < "$allow_patterns"
fi

# `--null` ends the file name with a NUL, so a colon in a path cannot move where the record is cut.
# The trailing `cat` keeps grep's stdout from being a file it might also be asked to scan.
# grep's status is classified: 0 = matched, 1 = no match, >1 = it could not scan the whole tree. A
# redirect on grep that cannot open would stop it with a 1, so that file is opened on its own first.
: > "$scan_errors" || write_failed
(cd "$ROOT" || exit 2
 grep -rIEn --null "$PATTERNS" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist . \
   2>"$scan_errors") | cat > "$raw_hits"
scan_status=("${PIPESTATUS[@]}")
[ "${scan_status[1]}" -eq 0 ] || write_failed
scan_rc=${scan_status[0]}
if [ "$scan_rc" -gt 1 ]; then
  echo "::error::secret-scan: the scan failed (exit $scan_rc), refusing to report clean"
  head -5 "$scan_errors"
  exit 1
fi

# unchanged_at_base <path> <text>: is this exact line in the base copy of the file? Always yes when
# the tree is the source of exceptions. Read through a temp file, not a pipe into `grep -q`: under
# pipefail, grep closing the pipe on its first match can fail the pipeline on a line that is there.
cached_path=""
unchanged_at_base() {
  [ "$base_mode" -eq 1 ] || return 0
  [ -n "$scan_base" ] || return 1
  if [ "$1" != "$cached_path" ]; then
    cached_path="$1"
    copy_from_base "$scan_base:$1" "$base_copy"
  fi
  grep -qFx -- "$2" "$base_copy"
}

# entry_is_directory <entry>: on the base commit when there is one, so a change cannot turn a listed
# file into a directory and exempt what it puts inside. Otherwise in the tree being scanned.
entry_is_directory() {
  if [ "$base_mode" -eq 0 ]; then
    [ -d "$ROOT/$1" ]
  else
    [ "$(git -C "$ROOT" cat-file -t "$scan_base:./$1" 2>/dev/null)" = tree ]
  fi
}

# listed_path <path>: the path, without its leading ./, equals an entry, or sits under an entry that is
# a directory. Compared as whole strings, because a substring match would let a new file named
# src/<entry>-real.ts take the exemption of <entry>. The quoted case pattern keeps an entry literal. An
# entry reading as path:line names that line, never a file of that name, or a change could add the file.
listed_path() {
  local rel="${1#./}" entry dir
  while IFS= read -r entry; do
    if [ "$rel" = "$entry" ] && ! [[ "${entry%:}" =~ :[0-9]+$ ]]; then return 0; fi
    dir="${entry%/}"
    [ -n "$dir" ] || continue
    case "$rel" in
      "$dir"/*) entry_is_directory "$dir" && return 0 ;;
    esac
  done < "$allow_patterns"
  return 1
}

# listed_line <path> <line>: the finding, without its leading ./, equals an entry written as path:line
# or path:line:, compared whole so that an entry for line 1 does not cover line 10.
listed_line() {
  local rel="${1#./}" entry
  while IFS= read -r entry; do
    [ "$rel:$2" = "${entry%:}" ] && return 0
  done < "$allow_patterns"
  return 1
}

# A listed path is exempt whatever it holds, changed or not: requiring an unchanged line there would
# leave no way to ever edit a line in such a file by PR. A listed line names what was reviewed, so it
# holds only while that line is unchanged from the base, or a change could put a new key on it. The
# other three exceptions depend on the line's own text or on the exception file, whose comments carry
# vendor-prefix placeholders, and hold under the same rule.
while IFS= read -r -d '' path && IFS= read -r body; do
  line_no="${body%%:*}"
  text="${body#*:}"
  listed_path "$path" && continue
  by_line=0
  listed_line "$path" "$line_no" && by_line=1
  [ "$path" = "./.github/.secret-allowlist" ] && by_line=1
  case "$text" in *'allowlist secret'*) by_line=1 ;; esac
  grep -qFf "$allow_patterns" <<<"$text" && by_line=1
  if [ "$by_line" -eq 1 ] && unchanged_at_base "$path" "$text"; then continue; fi
  printf '%s:%s\n' "${path//$'\n'/?}" "$line_no" >> "$findings" || write_failed
done < "$raw_hits"

if [ -s "$findings" ]; then
  # `::error::` is a GitHub Actions annotation; it is inert plain text everywhere else, which is
  # precisely why the same file can serve CI and a local run without branching on the environment.
  echo "::error::real-secret-shaped string outside the allowlist — do not commit credentials"
  cat "$findings"
  [ "$base_mode" -eq 0 ] || echo "note: an exception applies once it is on the base commit of this change"
  exit 1
fi
echo "secret-scan clean (allowlist-aware, fail-closed)"
