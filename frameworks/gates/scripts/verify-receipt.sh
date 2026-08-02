#!/usr/bin/env bash
# verify-receipt — decide whether a local-CI receipt actually vouches for a commit. (#929 scope 3.)
#
# run-local.sh WRITES receipts and, until now, nothing READ them. A receipt nobody verifies is not a
# receipt, it is a log line: it makes "local CI passed" look checkable without anyone ever checking.
# This is the reader, and it is the component where fail-closed has to be absolute.
#
# ⚠️ THIS IS AN INTEGRITY AID, NOT AN AUTHENTICATION MECHANISM. The receipt is unsigned and lives in
# a directory the local user can write. Anyone able to run this can also author a passing receipt by
# hand. It answers "did I actually run the gates over this exact commit, with these exact gate
# scripts" — which is the question that costs people hours. It does NOT answer "is this developer
# telling the truth", and nothing on a merge path may treat it as if it does. Signing it would buy
# tamper-evidence at the price of key management on every dev machine; not worth it for a tool whose
# threat model is "did I actually run this".
#
# Usage:  bash frameworks/gates/scripts/verify-receipt.sh [sha]      (default: HEAD)
# Exit:   0 = this commit is verified · 1 = NOT verified (reason named on stderr)
#
# Every ambiguous case is exit 1. A missing receipt, unparseable JSON, a missing field, an unknown
# gate — all "unverified". The one thing this must never do is let a question mark read as a pass.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frameworks/gates/scripts/lib/waveci-common.sh
. "$HERE/lib/waveci-common.sh"

fail() { echo "verify-receipt: UNVERIFIED — $*" >&2; exit 1; }

ROOT=$(git rev-parse --show-toplevel) || fail "not inside a git repo"
cd "$ROOT"

SHA="${1:-$(git rev-parse HEAD)}"
waveci_sha_ok "$SHA" || fail "'$SHA' is not a full 40-hex commit sha"

REPO=$(waveci_repo_name "$ROOT")
waveci_repo_name_ok "$REPO" || fail "unsafe repo name '$REPO'"

RECEIPT="$(waveci_receipt_dir)/${REPO}-${SHA}.json"
# Only the CLEAN receipt name is ever consulted. A dirty run writes `<repo>-<sha>-dirty-<id>.json`
# and is deliberately unreachable here: it attests uncommitted content, so it cannot vouch for a
# commit no matter what its gates reported. That distinction is the whole point of #934/#935 — before
# it, a dirty run overwrote the clean receipt at the same sha and this check would have passed on it.
[ -f "$RECEIPT" ] || fail "no receipt for $SHA (run: bash frameworks/gates/scripts/run-local.sh)"

# Expected gates come from the registry, not from the receipt. Asking the receipt which gates it
# should contain lets a receipt covering one gate certify a commit as fully gated — the check has to
# be against an independent source or it is circular.
# Rows are `id<TAB>script` — the registry states the script path and this must not reconstruct it.
# An id is not its filename: `file-size` -> `check-file-size.sh`. Guessing that mapping is precisely
# the bug that left run-local.sh's own default invocation broken from the day it shipped.
mapfile -t REGISTRY_ROWS < <(waveci_registry_gates) || fail "could not read frameworks/gates/registry.yaml"
[ "${#REGISTRY_ROWS[@]}" -gt 0 ] || fail "registry declares no runnable gates — refusing to certify"

# Parse and structurally validate in python (stdlib only — no jq dependency on a dev machine). It
# emits EITHER a single `!<reason>` line OR the `gate<TAB>sha256` rows — never both. Buffering the
# rows and printing them only on success matters: an earlier version printed rows as it went and
# then appended the failure line, so the caller's "does it start with !" test read a gate row and
# the failure was reported as an unsafe gate id. A status channel that can interleave with data is
# a status channel that will be misread.
parsed=$(python3 - "$RECEIPT" "$SHA" "${REGISTRY_ROWS[@]}" <<'PY'
import json, sys
path, want_sha = sys.argv[1], sys.argv[2]
expected = {row.split("\t", 1)[0] for row in sys.argv[3:]}

def bail(msg):
    print("!" + msg); sys.exit(0)

try:
    d = json.load(open(path))
except Exception as e:
    bail(f"receipt is not valid JSON ({type(e).__name__})")
if not isinstance(d, dict):
    bail("receipt is not a JSON object")
if d.get("sha") != want_sha:
    # A receipt whose filename says one commit and whose body says another has been hand-edited or
    # mis-keyed. Either way it is not evidence.
    bail(f"receipt body names {d.get('sha')!r}, not the requested commit")
if d.get("dirty") is not False:
    # Absent `dirty` means a pre-#935 receipt, which cannot distinguish clean from dirty. Treating
    # an unknowable as clean is the failure this whole chain exists to prevent, so it is unverified.
    bail("receipt is from a DIRTY tree, or predates dirty-tracking — it cannot vouch for a commit")
gates = d.get("gates")
if not isinstance(gates, list) or not gates:
    bail("receipt records no gates")

rows, seen = [], set()
for g in gates:
    if not isinstance(g, dict):
        bail("malformed gate entry")
    name, rc, gsha = g.get("gate"), g.get("exit_code"), g.get("gate_file_sha256")
    if not isinstance(name, str) or not isinstance(gsha, str):
        bail("gate entry missing 'gate' or 'gate_file_sha256'")
    if rc != 0:
        bail(f"gate '{name}' FAILED in this receipt (exit {rc})")
    seen.add(name)
    rows.append(f"{name}\t{gsha}")

missing = expected - seen
if missing:
    # A receipt for `secret-scan` alone must not read as "all gates passed".
    bail("receipt does not cover: " + ", ".join(sorted(missing)))
print("\n".join(rows))
PY
) || fail "could not parse $RECEIPT"

case "$parsed" in
  '!'*) fail "${parsed#!}" ;;
esac

# The load-bearing check. `gate_file_sha256` is what stops a receipt from vouching for a gate whose
# logic has since changed — a stale pass surviving the very edit that broke it. Compare against the
# gate AS OF THE COMMIT BEING VERIFIED (`git show <sha>:`), never the working tree: the tree may be
# dirty, or checked out elsewhere entirely, and then the comparison describes the wrong thing.
while IFS=$'\t' read -r gate recorded; do
  [ -n "$gate" ] || continue
  waveci_gate_id_ok "$gate" || fail "receipt names an unsafe gate id '$gate'"
  script=""
  for r in "${REGISTRY_ROWS[@]}"; do
    [ "${r%%$'\t'*}" = "$gate" ] && { script="${r#*$'\t'}"; break; }
  done
  [ -n "$script" ] || fail "receipt names '$gate', which the registry does not declare as runnable"
  actual=$(git show "$SHA:$script" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
  [ -n "$actual" ] || fail "gate '$gate' has no script at $script in $SHA"
  [ "$actual" = "$recorded" ] \
    || fail "gate '$gate' has CHANGED since this receipt was written — rerun run-local.sh"
done <<< "$parsed"

echo "verify-receipt: VERIFIED $SHA — ${#REGISTRY_ROWS[@]} gate(s) passed on a clean tree"
