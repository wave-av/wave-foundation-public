#!/usr/bin/env bash
# check-pr-ambiguity.sh — advisory check that a PR body ran the Ambiguity Gate.
#
# Mirrors frameworks/hooks/validate-conventional-title.sh in style: read input from an arg, a file path,
# or stdin; one rule; clear stderr guidance. It is ADVISORY — wired into semantic-pr.yml under
# continue-on-error: true (per DECISIONS.md ADR-006: gates are additive + advisory, never a merge block).
#
# The rule (two parts):
#   1. The PR body MUST contain an "Ambiguity Gate" section (the PR-template checklist heading).
#   2. IF the "hard-to-reverse / crosses a public<->private boundary" checklist box is CHECKED ([x]),
#      the body MUST also reference a recorded decision (an "ADR-" id or "DECISIONS.md"). Acting on a
#      hard-to-reverse / boundary-crossing change without a linked ADR is exactly what the gate prevents.
#
# Usage:  check-pr-ambiguity.sh "<pr-body>"           # arg form (a literal body string)
#         check-pr-ambiguity.sh <path-to-body-file>   # arg is an existing file → read it
#         echo "<pr-body>" | check-pr-ambiguity.sh     # stdin form
# Exit:   0 = ok (gate present, and an ADR is linked when a hard-to-reverse box is checked)
#         2 = usage / advisory finding (missing checklist, or checked box without an ADR reference)
#
# NOTE: exit 2 is ADVISORY. In CI it runs under continue-on-error, so it surfaces a notice, never blocks.
set -eu

body="${1-}"
# Three calling conventions, all funnelling to one rule:
#   - a literal PR-body string                       (CI: passed as "$PR_BODY")
#   - a path to a file containing the body           (local convenience)
#   - the body on stdin                              (echo "..." | check-...)
if [ -n "$body" ] && [ -f "$body" ]; then
  body="$(cat "$body")"
elif [ -z "$body" ] && [ ! -t 0 ]; then
  body="$(cat)"
fi

note() { printf '%s\n' "$@" >&2; }

if [ -z "$body" ]; then
  note "ambiguity-gate: ⚠ empty PR body — add the '## Ambiguity Gate' checklist." \
    "  See frameworks/ambiguity-gate/README.md"
  exit 2
fi

# 1) The Ambiguity Gate section must be present. Match the heading case-insensitively, tolerating any
#    leading '#' level. grep -i avoids a tr round-trip; the regex anchors to a markdown heading line.
if ! printf '%s\n' "$body" | grep -qiE '^[[:space:]]*#+[[:space:]]*ambiguity gate'; then
  note "ambiguity-gate: ⚠ no '## Ambiguity Gate' section found in the PR body." \
    "  Add the checklist from .github/pull_request_template.md, or run the gate:" \
    "  DETECT → RESEARCH → RECORD (DECISIONS.md) → ACT. See frameworks/ambiguity-gate/README.md" \
    "  (advisory — this does not block the merge.)"
  exit 2
fi

# 2) If a 'hard-to-reverse / public<->private boundary / one-of-N-canonical' box is checked, require an
#    ADR reference. A checked GitHub box is '- [x]' (x any case); we look for the gate's reversibility
#    line specifically — the words 'hard-to-reverse' OR 'public' on a checked checklist line.
checked_hard_to_reverse="$(
  printf '%s\n' "$body" |
    grep -iE '^[[:space:]]*[-*][[:space:]]*\[[xX]\]' |
    grep -iE 'hard-to-reverse|public.?private|public.?↔.?private|public<->private|one of n|n canonical|canonical thing' ||
    true
)"

# A *real* ADR reference, not the template's own placeholder/instructions. Strip ALL checklist lines
# (both '- [ ]' and '- [x]' — the checklist label itself carries the literal "(Refs DECISIONS.md
# ADR-xxx)" hint text) and HTML comments, then look in the remaining prose for a concrete ADR id
# (digits, not the "xxx" placeholder) or a DECISIONS.md mention. The reference belongs in the
# Summary/prose, not inside a checkbox label.
real_refs="$(
  printf '%s\n' "$body" |
    grep -ivE '^[[:space:]]*[-*][[:space:]]*\[[[:space:]xX]\]' |
    grep -ivE '<!--|-->'
)"
has_adr="$(printf '%s\n' "$real_refs" | grep -iE 'ADR-[0-9]|DECISIONS\.md' || true)"

if [ -n "$checked_hard_to_reverse" ] && [ -z "$has_adr" ]; then
  note "ambiguity-gate: ⚠ a hard-to-reverse / boundary / one-of-N box is checked but no ADR is linked." \
    "  Record the decision and reference it, e.g.  Refs DECISIONS.md ADR-006" \
    "  (frameworks/ambiguity-gate/DECISIONS.md is the canonical ADR home.)" \
    "  (advisory — this does not block the merge.)"
  exit 2
fi

echo "ambiguity-gate: ✓ gate checklist present${has_adr:+, ADR referenced}"
exit 0
