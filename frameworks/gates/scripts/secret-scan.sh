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
# Exit:   0 = clean · 1 = credential-shaped string found outside the allowlist, OR a malformed
#         allowlist (#932) — both are gate failures, because a config file that cannot be parsed
#         must never resolve to "no findings".
# Pure + read-only: no network, no writes, no token, no environment inputs.
set -uo pipefail

ROOT="${1:-.}"
# Resolved against ROOT, not cwd. Read from cwd it would scan the tree you NAMED while applying the
# exceptions of the tree you happen to be STANDING IN — a gate reporting on ambient state instead of
# its argument. No behaviour change for the registered invocation (`pass_filenames: false` -> ROOT="."
# -> `./.github/...`); it only makes `secret-scan.sh <other-tree>` mean what it reads like.
ALLOWLIST="$ROOT/.github/.secret-allowlist"

# Real-secret shapes. Lines tagged `pragma: allowlist secret` are skipped, which is how a vetting
# module or a test fixture can define key SHAPES without tripping the gate that looks for them.
PATTERNS='(sk-[A-Za-z0-9]{20}|sk_(live|test)_[A-Za-z0-9]{20}|npm_[A-Za-z0-9]{30}|sbp_[a-f0-9]{40}|github_pat_[A-Za-z0-9_]{40}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30}|AIzaSy[A-Za-z0-9_-]{20}|xai-[A-Za-z0-9]{40}|xoxb-[A-Za-z0-9-]+|-----BEGIN [A-Z ]*PRIVATE KEY)'

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
allow_patterns=$(mktemp)
trap 'rm -f "$allow_patterns"' EXIT
[ -f "$ALLOWLIST" ] && grep -vE '^[[:space:]]*($|#)' "$ALLOWLIST" > "$allow_patterns" || true

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
  local n=0 bad=0 line stripped
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
  if [ "$n" -gt 0 ] && [ ! -s "$allow_patterns" ]; then
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
      */*) [ -e "$ROOT/$entry" ] || echo "note: $ALLOWLIST: '$entry' matches no path under $ROOT — stale exception?" ;;
    esac
  done < "$allow_patterns"
fi

# The allowlist is excluded from the SCAN because its entire purpose is to enumerate credential
# SHAPES — its own comments carry vendor-prefix placeholders. It used to exclude itself by
# accident (its comment lines were also patterns); now that comments are stripped from the pattern
# set, that accident is gone and the exclusion has to be deliberate.
HITS=$(grep -rIEn "$PATTERNS" \
         --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist \
         --exclude="$(basename "$ALLOWLIST")" "$ROOT" 2>/dev/null \
       | grep -v 'allowlist secret' \
       | grep -vFf "$allow_patterns")

if [ -n "$HITS" ]; then
  # `::error::` is a GitHub Actions annotation; it is inert plain text everywhere else, which is
  # precisely why the same file can serve CI and a local run without branching on the environment.
  echo "::error::real-secret-shaped string outside the allowlist — do not commit credentials"
  echo "$HITS"
  exit 1
fi
echo "secret-scan clean (allowlist-aware, fail-closed)"
