#!/usr/bin/env bash
# test-verify-receipt.sh — self-test for frameworks/gates/scripts/verify-receipt.sh.
#
# The verifier's whole job is to say NO. Every interesting case is a refusal, and a refusal that
# silently becomes an acceptance is invisible — the build goes green and nobody looks. So this suite
# is weighted almost entirely toward "does it still reject", with exactly one positive case to prove
# it is not simply rejecting everything (a verifier that always fails is as useless as one that
# always passes, and much easier to ship by accident).
#
# Receipts are synthesized into a temp WAVECI_RECEIPTS dir; nothing here runs a container or touches
# the real receipt store.
#
# Usage:  bash frameworks/gates/test-verify-receipt.sh
# Exit:   0 = every case behaved as specified · 1 = at least one regressed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# `../..` — this file lives in frameworks/gates/, so one level up is frameworks/, not the repo root.
# Getting it wrong made every registry read fail and left the suite reporting on an empty gate list.
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
VERIFY="$HERE/scripts/verify-receipt.sh"
[ -f "$VERIFY" ] || { echo "error: $VERIFY not found" >&2; exit 1; }

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
export WAVECI_RECEIPTS="$work/receipts"
mkdir -p "$WAVECI_RECEIPTS"

cd "$REPO_ROOT" || { echo "error: cannot enter repo root '$REPO_ROOT'" >&2; exit 1; }
SHA=$(git rev-parse HEAD)
REPO=$(basename "$(git config --get remote.origin.url)" .git)

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# The real gate list and real hashes, so the positive case is genuinely valid rather than a fixture
# that happens to satisfy a weaker check.
gates_json() {
  python3 - "$SHA" <<'PY'
import re, subprocess, sys, pathlib, hashlib, json
sha = sys.argv[1]
txt = pathlib.Path("frameworks/gates/registry.yaml").read_text()
out = []
for gid, script in re.findall(r"^  - id:\s*(\S+)(?:.|\n)*?^    script:\s*(\S+)", txt, re.M):
    if not script.startswith("frameworks/gates/scripts/"):
        continue
    blob = subprocess.run(["git", "show", f"{sha}:{script}"], capture_output=True).stdout
    out.append({"gate": gid, "gate_file_sha256": hashlib.sha256(blob).hexdigest(),
                "exit_code": 0, "output_sha256": "0" * 64})
print(json.dumps(out))
PY
}
GATES=$(gates_json)

# write_receipt <json-body>
write_receipt() { printf '%s' "$1" > "$WAVECI_RECEIPTS/${REPO}-${SHA}.json"; }
receipt_with() {  # receipt_with <dirty> <gates-json>
  printf '{"repo":"%s","sha":"%s","dirty":%s,"tree_id":"x","host":"h","image":"i","ts":"t","gates":%s}' \
    "$REPO" "$SHA" "$1" "$2"
}

# expect <case> <want_exit> <want_substring|-> ; reads the receipt already on disk
expect() {
  local name="$1" want_exit="$2" want_text="$3" out rc
  out="$(bash "$VERIFY" "$SHA" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want_exit" ]; then
    fail "$name — exit $rc, want $want_exit"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"; return
  fi
  if [ "$want_text" != "-" ] && ! printf '%s' "$out" | grep -qF "$want_text"; then
    fail "$name — exit correct, but never says '$want_text'"; printf '       %s\n' "$(printf '%s' "$out" | head -2)"; return
  fi
  pass "$name"
}

echo "== the positive case — it must still be able to say yes =="
write_receipt "$(receipt_with false "$GATES")"
expect "P  complete, clean, current      -> VERIFIED" 0 "VERIFIED"

echo "== absence and ambiguity are UNVERIFIED, never a pass =="

# The default. Nothing ran, so nothing is proven — this is the case that must never drift to 0.
rm -f "$WAVECI_RECEIPTS/${REPO}-${SHA}.json"
expect "A  no receipt at all             -> unverified" 1 "no receipt for"

# A receipt that cannot be parsed tells you nothing. "Nothing" is not "clean".
write_receipt 'not json at all'
expect "B  unparseable JSON              -> unverified" 1 "not valid JSON"

write_receipt "$(receipt_with false '[]')"
expect "C  empty gates array             -> unverified" 1 "records no gates"

echo "== the #934/#935 property: a dirty run must never vouch for a commit =="

write_receipt "$(receipt_with true "$GATES")"
expect "D  dirty:true                    -> unverified" 1 "DIRTY"

# A pre-#935 receipt has no `dirty` field, so clean and dirty are indistinguishable in it. Treating
# an unknowable as clean is exactly the failure the chain exists to prevent.
write_receipt "$(printf '{"repo":"%s","sha":"%s","host":"h","image":"i","ts":"t","gates":%s}' "$REPO" "$SHA" "$GATES")"
expect "E  legacy receipt, no dirty field -> unverified" 1 "predates dirty-tracking"

echo "== partial and stale receipts must not certify =="

# A receipt for ONE gate must not read as "all gates passed" — the expected set comes from the
# registry, never from the receipt, or the check is circular.
write_receipt "$(receipt_with false "$(printf '%s' "$GATES" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[:1]))')")"
expect "F  covers only one gate          -> unverified" 1 "does not cover"

# The load-bearing check: a receipt must not keep vouching for a gate whose logic has since changed.
write_receipt "$(receipt_with false "$(printf '%s' "$GATES" | python3 -c '
import json,sys
g=json.load(sys.stdin); g[0]["gate_file_sha256"]="0"*64; print(json.dumps(g))')")"
expect "G  gate script has CHANGED       -> unverified" 1 "has CHANGED"

write_receipt "$(receipt_with false "$(printf '%s' "$GATES" | python3 -c '
import json,sys
g=json.load(sys.stdin); g[0]["exit_code"]=1; print(json.dumps(g))')")"
expect "H  a gate FAILED in the receipt  -> unverified" 1 "FAILED in this receipt"

# Filename says one commit, body says another: hand-edited or mis-keyed, either way not evidence.
write_receipt "$(printf '{"repo":"%s","sha":"%s","dirty":false,"tree_id":"x","host":"h","image":"i","ts":"t","gates":%s}' \
  "$REPO" "0000000000000000000000000000000000000000" "$GATES")"
expect "I  body names a different commit -> unverified" 1 "not the requested commit"

# A gate the registry does not declare cannot be certified — and the id reaches a path, so it is
# charset-checked before it is used for anything.
write_receipt "$(receipt_with false "$(printf '%s' "$GATES" | python3 -c '
import json,sys
g=json.load(sys.stdin); g.append({"gate":"../../etc/passwd","gate_file_sha256":"0"*64,"exit_code":0,"output_sha256":"0"*64}); print(json.dumps(g))')")"
expect "J  traversal-shaped gate id      -> unverified" 1 "unsafe gate id"

echo
if [ "$fails" -eq 0 ]; then
  echo "verify-receipt self-test: all cases pass"; exit 0
fi
echo "verify-receipt self-test: $fails case(s) FAILED"; exit 1
