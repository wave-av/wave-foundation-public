#!/usr/bin/env bash
# Gate self-test: the auto-merge sweep in .github/workflows/automerge.yml.
#
# WHY THIS EXISTS (#1171): the sweep read each candidate PR with an unguarded command substitution.
# The Actions default shell is `bash -e`, so ONE transient API error on the FIRST candidate aborted
# the whole step — 99 of its last 100 scheduled runs failed, zero succeeded, and a labeled PR sat
# unmerged for 12 days while the run history read as "just failing". Nothing in the repo covered it.
#
# The body under test is EXTRACTED FROM THE WORKFLOW at run time, never copied here. A copy would
# drift the moment someone edited the workflow, and this file would keep passing while covering
# nothing — the same silent-staleness failure the sweep itself had.
#
# Discovered by .github/workflows/self-check.yml via `git ls-files 'frameworks/gates/test-*.sh'`,
# so it runs on every PR without being enumerated anywhere.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)" || { echo "not in a git work tree" >&2; exit 2; }

# MIRROR GUARD. frameworks/gates/test-*.sh publish to the public open-core mirror, but
# .github/workflows/automerge.yml stays PRIVATE — so in the mirror there is no sweep to drill and
# this test must skip, not fail. The path is named literally (not just via $WF) because that is the
# only form scripts/sync-public.sh can recognise; a variable-only guard is reported as a missing dep.
#
# This is NOT the fail-open shape that #928 warns about. It distinguishes "the subject of this test
# does not exist in this tree" from "the test could not do its job": once the workflow IS present,
# every downstream failure below stays hard, including an extraction that comes back empty.
[ -f "$ROOT/.github/workflows/automerge.yml" ] || {
  echo "SKIP: .github/workflows/automerge.yml not in this tree (open-core mirror) — no sweep to drill"
  exit 0
}
WF="$ROOT/.github/workflows/automerge.yml"

# Private temp dir; removed on every exit path (including failure).
STUB="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
chmod 700 "$STUB"
trap 'rm -rf "$STUB"' EXIT
BODY="$STUB/sweep-body.sh"

# --- extract the sweep step's `run:` block ------------------------------------------------------
# Pure-stdlib parse (no PyYAML: the runner is not guaranteed to have it). Finds the step whose body
# performs the enqueue, then takes the `run: |` scalar and dedents it. An empty or missing result is
# a HARD ERROR — never a green "0 tests", which is the fail-open shape that disabled this repo's
# secret scan (#928).
python3 - "$WF" "$BODY" <<'PY' || { echo "FATAL: could not extract the sweep body from the workflow" >&2; exit 2; }
import sys

src, dst = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().splitlines()

start = None
for i, ln in enumerate(lines):
    if ln.strip() == "- name: Sweep ready labeled PRs":
        start = i
        break
if start is None:
    sys.exit("no step named 'Sweep ready labeled PRs'")

run_at = None
for i in range(start, len(lines)):
    if lines[i].strip() in ("run: |", "run: |-"):
        run_at = i
        break
    # stop if we fell into the next step before finding a run: block
    if i > start and lines[i].lstrip().startswith("- name:"):
        break
if run_at is None:
    sys.exit("the sweep step has no 'run: |' block")

indent = len(lines[run_at]) - len(lines[run_at].lstrip())
body = []
for ln in lines[run_at + 1:]:
    if ln.strip() and (len(ln) - len(ln.lstrip())) <= indent:
        break
    body.append(ln[indent + 2:] if len(ln) > indent + 2 else "")

if not any(l.strip() for l in body):
    sys.exit("extracted sweep body is empty")
if "enqueuePullRequest" not in "\n".join(body):
    sys.exit("extracted block does not look like the sweep (no enqueuePullRequest)")

open(dst, "w", encoding="utf-8").write("\n".join(body) + "\n")
PY

export PATH="$STUB:$PATH"
export REPO="wave-av/wave-foundation"

# --- the `gh` test double -----------------------------------------------------------------------
# Every gh invocation is intercepted and logged; anything unrecognised exits 2 rather than falling
# through to a real gh. No network, no credentials, no real PR is ever touched.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env python3
import json, os, sys, pathlib

a = sys.argv[1:]
log = os.environ["CALLLOG"]
fail_read = set(filter(None, os.environ.get("FAIL_READ", "").split(",")))
queued_prs = set(filter(None, os.environ.get("QUEUED", "").split(",")))
states = json.loads(os.environ.get("STATES", "{}"))

def rec(s):
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(s + "\n")

if a[:2] == ["pr", "list"]:
    rec("list")
    print("\n".join(filter(None, os.environ["PRS"].split(","))))
    sys.exit(0)

if a[:2] == ["pr", "update-branch"]:
    rec("update-branch " + a[2])
    sys.exit(0)

if a[:2] == ["pr", "view"]:
    # Modelled ONLY so the negative control reproduces #1171 exactly. The pre-fix sweep read state
    # with `gh pr view --json ...,mergeQueueEntry`; that field exists on the GraphQL PullRequest
    # type but is NOT exposed by `gh pr view --json`, so real gh exits 1 printing its valid-field
    # list. Under `bash -e` that killed the whole step on the first candidate. Reproduce that.
    n = a[2]
    fields = next((a[i + 1] for i, x in enumerate(a) if x == "--json"), "")
    rec("read " + n)
    if "mergeQueueEntry" in fields:
        print("Unknown JSON field: \"mergeQueueEntry\"", file=sys.stderr)
        sys.exit(1)
    if n in fail_read:
        print("gh: transient API error on #%s" % n, file=sys.stderr)
        sys.exit(1)
    print(states.get(n, "CLEAN"))
    sys.exit(0)

if a[:2] == ["api", "graphql"]:
    query = next((a[i + 1] for i, x in enumerate(a) if x == "-f" and a[i + 1].startswith("query=")), "")
    body = query[len("query="):]

    if body.startswith("mutation"):
        gid = next(a[i + 1] for i, x in enumerate(a) if x == "-f" and a[i + 1].startswith("id="))[3:]
        oid = next(a[i + 1] for i, x in enumerate(a) if x == "-f" and a[i + 1].startswith("oid="))[4:]
        rec("ENQUEUE id=%s oid=%s" % (gid, oid))
        print(json.dumps({"data": {"enqueuePullRequest": {"mergeQueueEntry": {"position": 1}}}}))
        sys.exit(0)

    n = next(a[i + 1].split("=", 1)[1] for i, x in enumerate(a) if x == "-F" and a[i + 1].startswith("p="))
    rec("read " + n)
    if n in fail_read:
        print("gh: transient API error on #%s" % n, file=sys.stderr)
        sys.exit(1)

    mss = states.get(n, "CLEAN")

    if mss == "__nopr__":
        # GitHub returns a null pullRequest for a number that no longer resolves. What gh PRINTS for
        # that depends on the --jq the workflow passes, so this double reads the real filter instead
        # of hardcoding one answer -- hardcoding is how a stub hands the code under test a free pass.
        #   with `select(. != null)`  -> the null is filtered out, jq emits NOTHING (#1176 fixed)
        #   without it                -> string interpolation renders each null as the literal TEXT
        #                                "null", so gh prints `null - null null` and exits 0
        jq_expr = next((a[i + 1] for i, x in enumerate(a) if x == "--jq"), "")
        if "select(. != null)" in jq_expr:
            sys.exit(0)
        print("null - null null")
        sys.exit(0)

    if mss == "__lazy__":
        # Mergeability is computed LAZILY: the first ask can answer UNKNOWN and resolve on a retry.
        counter = pathlib.Path(log + ".lazy" + n)
        seen = int(counter.read_text()) if counter.exists() else 0
        counter.write_text(str(seen + 1))
        mss = "UNKNOWN" if seen < 1 else "CLEAN"

    print("%s %s PR_node_%s oid%s000000" % (mss, "QUEUED" if n in queued_prs else "-", n, n))
    sys.exit(0)

rec("UNEXPECTED " + " ".join(a))
sys.exit(2)
STUBEOF
chmod +x "$STUB/gh"

# The body sleeps 3s between UNKNOWN retries. Stub it to keep the suite fast; only timing changes,
# never the number of retries or the control flow being asserted.
printf '#!/bin/sh\nexit 0\n' > "$STUB/sleep"
chmod +x "$STUB/sleep"

# The sweep calls `node scripts/merge-queue-health.mjs` as its #1187 circuit-breaker. That breaker
# is a separate component with its own exit-code contract (0 under-budget · 1 alarm · 2 undetermined
# · 3 exhausted); this test drills the SWEEP's enqueue logic, not the breaker's timeline read, so the
# breaker is stubbed under-budget (exit 0). Anything else that invokes node still delegates to the
# REAL node — resolved BEFORE the stub shadows PATH, so there is no recursion.
NODE_BIN="$(command -v node)"
cat > "$STUB/node" <<NODESTUB
#!/bin/sh
case "\$*" in
  *merge-queue-health.mjs*) exit 0 ;;  # under budget — breaker drilled separately
esac
exec "$NODE_BIN" "\$@"
NODESTUB
chmod +x "$STUB/node"

pass=0
fail=0

drill() { # <name> <PRS> <FAIL_READ> <QUEUED> <STATES-json> <want-enqueued-csv> <want-rc>
  local name="$1" want_enq="$6" want_rc="$7"
  export PRS="$2" FAIL_READ="$3" QUEUED="$4" STATES="$5"
  export CALLLOG="$STUB/calls"
  : > "$CALLLOG"
  rm -f "$STUB"/calls.lazy* 2>/dev/null

  local out rc got reads
  out="$(bash -e "$BODY" 2>&1)"
  rc=$?
  got="$(grep '^ENQUEUE ' "$CALLLOG" | sed -E 's/^ENQUEUE id=PR_node_([0-9]+).*/\1/' | paste -sd, -)"
  reads="$(grep -c '^read ' "$CALLLOG" || true)"

  if [ "$got" = "$want_enq" ] && [ "$rc" = "$want_rc" ]; then
    pass=$((pass + 1))
    printf 'ok   %-38s rc=%s enqueued=[%s] reads=%s\n' "$name" "$rc" "$got" "$reads"
  else
    fail=$((fail + 1))
    local shown="       ${out//$'\n'/$'\n'       }"
    printf 'FAIL %-38s rc=%s (want %s) enqueued=[%s] (want [%s])\n%s\n' \
      "$name" "$rc" "$want_rc" "$got" "$want_enq" "$shown"
  fi
}

echo "=== the #1171 regression: a failure on the FIRST candidate must not kill the sweep ==="
# Discriminating on purpose. Planting the failure on the LAST PR would pass against the BROKEN
# workflow too, and would prove nothing.
drill "1st read fails, rest still sweep"  "1170,1172,1049" "1170"      ""     '{}' "1172,1049" 1
drill "every read fails, none enqueued"   "1170,1172"      "1170,1172" ""     '{}' ""          1

echo
echo "=== ordinary behaviour ==="
drill "CLEAN and UNSTABLE both enqueue"   "1170,1172" "" ""     '{"1170":"CLEAN","1172":"UNSTABLE"}' "1170,1172" 0
drill "already queued is skipped"         "1170,1172" "" "1170" '{}'                                 "1172"      0
drill "BEHIND updates the branch instead" "1170,1172" "" ""     '{"1170":"BEHIND"}'                   "1172"      0
drill "DIRTY is not ready, skipped"       "1170,1172" "" ""     '{"1170":"DIRTY"}'                    "1172"      0
drill "lazy UNKNOWN retries, then queues" "1170"      "" ""     '{"1170":"__lazy__"}'                 "1170"      0
# A null pullRequest (deleted, or no longer visible) is UNREADABLE state, not a verdict of
# "not ready" — jq renders the null as the literal text "null", which would otherwise sail past the
# empty-output guard and be skipped inside a GREEN run. It must be counted as an error (#1176), so
# the sweep still processes the remaining PRs but the run ends red.
drill "null PR counted as an error"       "1170,1172" "" ""     '{"1170":"__nopr__"}'                 "1172"      1

echo
echo "=== API budget: exactly ONE read per PR ==="
export PRS="1170,1172,1049" FAIL_READ="" QUEUED="" STATES='{}' CALLLOG="$STUB/calls"
: > "$CALLLOG"
bash -e "$BODY" >/dev/null 2>&1
reads="$(grep -c '^read ' "$CALLLOG" || true)"
if [ "$reads" = 3 ]; then
  pass=$((pass + 1))
  echo "ok   3 PRs cost 3 reads (one round trip each)"
else
  fail=$((fail + 1))
  echo "FAIL 3 PRs cost $reads reads, expected 3"
fi

if grep -q '^UNEXPECTED ' "$STUB/calls"; then
  fail=$((fail + 1))
  echo "FAIL the sweep made a gh call this double does not model:"
  grep '^UNEXPECTED ' "$STUB/calls" | sed 's/^/       /'
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
