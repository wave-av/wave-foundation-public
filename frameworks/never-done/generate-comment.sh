#!/usr/bin/env bash
# generate-comment.sh
#
# Parses a PR body for closure-pattern markers (closes #N, fixes #N,
# WAVE-NNNNN). Emits the never-done audit-prompts comment to stdout.
#
# Usage:
#   generate-comment.sh < pr-body.md
#   echo "$PR_BODY" | generate-comment.sh
#
# Exit codes:
#   0 — closure pattern(s) detected; comment emitted.
#   2 — no closure pattern; nothing emitted (caller should skip posting).
#
# Patterns recognised (case-insensitive, outside code blocks):
#   closes #N, fixes #N, resolves #N            (GitHub)
#   WAVE-N, [WAVE-N], Closes: WAVE-N            (Linear)

set -euo pipefail

body=$(cat)

# Strip fenced code blocks (``` ... ```) so we don't false-match on examples.
stripped=$(printf '%s' "$body" | awk '
  /^[[:space:]]*```/ { fenced = !fenced; next }
  !fenced { print }
')

# Detect closure patterns.
gh_closes=$(printf '%s' "$stripped" | grep -oiE '\b(closes|fixes|resolves)[[:space:]]+#[0-9]+' | sort -u || true)
linear_keys=$(printf '%s' "$stripped" | grep -oE '\bWAVE-[0-9]+' | sort -u || true)

if [ -z "$gh_closes" ] && [ -z "$linear_keys" ]; then
  exit 2
fi

# Emit the comment.
cat <<'EOF'
## :ear: Closure audit — invitation, not a blocker

Detected closure markers on this PR. Per
[`rules/never-done.md`](../../rules/never-done.md), every closure is an
invitation to file follow-ups — not an exit. 60 seconds on each prompt:

- [ ] **Intent** — did this deliver the closed issue's intent fully? If partial, what's left, and is that tracked?
- [ ] **Regressions** — what could break that nobody tested? Newly-frequent or never-reached paths?
- [ ] **New affordances** — what becomes possible because this landed? File features OR guards as needed.
- [ ] **Deferred / hand-waved** — anything stubbed / TODO'd / "later"? File NOW while context is fresh.
- [ ] **Consumers** — who depends on the surface this changed? All compat-checked / notified?
- [ ] **Re-audit cadence** — re-look in 1 week / 1 release / 1 quarter? File a scheduled audit if non-trivial.
- [ ] **Operational follow-up** — monitoring / alerting / runbook / on-call gaps?
- [ ] **Doc drift** — does any doc, README, schema, or registry now misrepresent reality?

### Reply with one of:

**Option A:** `Follow-ups: WAVE-NNNN (regression test), WAVE-NNNN (new flag), …`

**Option B:** `No follow-ups identified after audit.`

Either reply is fine. **This check does not block merging.**
EOF

exit 0
