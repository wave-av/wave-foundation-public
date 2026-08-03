#!/usr/bin/env bash
# test-workflow-policy.sh — self-test for the WAS (Workflow Authoring Standard) workflow-policy
# lint that is INLINED in .github/workflows/checks.yml (step "Workflow-policy enforce").
#
# Closes the "fleet-blast brake doesn't test its payload" gap: advance-major-tag.sh already
# self-tests emit.py --check and the claude-api request-shape linter before force-moving the v1
# tag, but had NO coverage for the WAS rules 1-5 — a broken rule could ship fleet-wide undetected.
#
# checks.yml is the live enforce keystone AND a reusable workflow (runs against the CALLER's
# checkout), which is why the lint is inlined there rather than a vendored script. Nothing here
# duplicates that python — the shared harness SOURCES it verbatim from checks.yml, so if the inline
# lint changes this test automatically tests the new version, with nothing to keep in sync by hand.
#
# SCOPE: the ENFORCE path (rules 1-5 fixtures) plus the rule registry's structure and provenance.
# The SHADOW path — shadow rules' fixtures and canary-enforce routing — is the sibling suite,
# test-workflow-policy-shadow.sh, split out when rule9 (#1020) pushed this file past the ~6000-token
# hard gate. Both are discovered independently by the gate-self-tests job.
#
# shellcheck disable=SC2154
# ^ work/lint_py/FIXTURES are assigned by the harness sourced below. The source= directive on that
# line says where to look, but it is only acted on under -x, which the repo's shell ratchet does not
# pass — so without this suppression the ratchet reports every harness-provided variable unassigned.
# (Keep every continuation line from starting with the literal directive prefix: any comment opening
# that way is parsed AS a directive, which is SC1072 "expected = after directive key".)
set -euo pipefail

# shellcheck source=lib/workflow-policy-harness.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workflow-policy-harness.sh"

fail=0

# --- shared SEVERITY-dict extractor (brace-balanced, handles the 3rd canary-enforce dict form) ---
# A naive `re.search(r"\{(.*?)\}", ..., re.S)` is lazy and would stop at the FIRST '}' it sees —
# which, once a rule's value is itself a dict ({"mode": "canary-enforce", "repos": [...]}), is the
# INNER closing brace, not SEVERITY's own. Scan for the balanced outer '{...}' (string-aware, so a
# literal '{' or '}' inside a repo name can't desync the count) and literal_eval the real dict.
# Written to disk (not inlined via unquoted heredoc) so no shell interpolation ever touches it.
severity_extract_py="$work/severity_extract.py"
cat >"$severity_extract_py" <<'EXTRACTSEV'
import ast, sys
def extract_severity_dict(src):
    # Anchor on the actual assignment, not any mention of the word "SEVERITY" (comments above the
    # dict describe the canary-enforce dict SHAPE in prose, e.g. '{"mode": ..., "repos": [...]}' —
    # matching on "SEVERITY" alone would latch onto a comment's illustrative braces instead).
    i = src.index("SEVERITY = {")
    i = src.index("{", i)
    depth = 0
    in_str = False
    str_ch = ""
    esc = False
    in_comment = False
    j = i
    while j < len(src):
        c = src[j]
        if in_comment:
            if c == "\n":
                in_comment = False
            j += 1
            continue
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == str_ch:
                in_str = False
        else:
            if c == "#":
                # Inline comment (e.g. explaining rule7's shadow entry) — skip to end of line.
                # Must check BEFORE quote-handling: a '#' inside a dict value never opens one of
                # these top-level comments (it'd already be inside in_str), so this is unambiguous.
                in_comment = True
                j += 1
                continue
            if c in "\"'":
                in_str = True
                str_ch = c
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    return ast.literal_eval(src[i:j])
        j += 1
    sys.exit("SEVERITY map: unbalanced braces while scanning")
EXTRACTSEV

# --- WAS joint #3 Layer 1 (+ Layer 3-2 canary-enforce): severity-structure assertion ---
# The lint carries a per-rule SEVERITY map with THREE valid value shapes: "enforce", "shadow", or
# {"mode": "canary-enforce", "repos": [...]}. Guard invariants against drift:
#   (1) every rule id passed to w("ruleX", ...) has a SEVERITY entry (no unmapped rule silently
#       defaulting to shadow),
#   (2) rules 1-5 stay "enforce" (nobody silently demotes a live fleet rule), and
#   (3) every dict-shaped value is well-formed: mode == "canary-enforce" and repos is a non-empty
#       list of non-empty strings (a malformed canary entry must fail closed, not silently shadow
#       everywhere or enforce everywhere).
# Provenance (every ENFORCE/canary-enforce rule has a promotion record) is Layer 1-2 below.
sev_out="$(python3 - "$lint_py" "$severity_extract_py" <<'SEVCHECK'
import re, sys
lint_py, extractor_py = sys.argv[1], sys.argv[2]
exec(open(extractor_py).read())
src = open(lint_py).read()
sev = extract_severity_dict(src)
called = sorted(set(re.findall(r'\bw\(\s*"(\w+)"', src)))
problems = []
for rid in called:
    if rid not in sev:
        problems.append(f"rule id '{rid}' is passed to w() but has no SEVERITY entry")
for rid in ("rule1", "rule2", "rule3", "rule4", "rule5"):
    if sev.get(rid) != "enforce":
        problems.append(f"{rid} must stay 'enforce' (grandfathered live rule) but is '{sev.get(rid)}'")
for rid, val in sev.items():
    if isinstance(val, str):
        if val not in ("enforce", "shadow"):
            problems.append(f"{rid}: unrecognized string severity '{val}' (must be enforce/shadow)")
    elif isinstance(val, dict):
        if val.get("mode") != "canary-enforce":
            problems.append(f"{rid}: dict severity must have mode=='canary-enforce', got {val.get('mode')!r}")
        repos = val.get("repos")
        if not isinstance(repos, list) or not repos or not all(isinstance(r, str) and r for r in repos):
            problems.append(f"{rid}: canary-enforce 'repos' must be a non-empty list of non-empty strings, got {repos!r}")
    else:
        problems.append(f"{rid}: SEVERITY value must be a string or dict, got {type(val).__name__}")
if problems:
    sys.exit("; ".join(problems))
print(f"mapped={len(sev)} called={called}")
SEVCHECK
)" && sev_rc=0 || sev_rc=$?
if [ "${sev_rc:-0}" -ne 0 ]; then
  echo "FAIL severity-structure: $sev_out"
  fail=1
else
  echo "PASS severity-structure ($sev_out)"
fi

# --- WAS joint #3 Layer 1-2 (+ Layer 3-2 canary-enforce): provenance assertion (F3) ---
# A PR could otherwise ship `"ruleN": "enforce"` (or a canary-enforce entry) directly, skipping the
# measured/gated promotion. Assert the ledger is the SSOT for enforce state:
#   enforce in the lint          <=> latest ledger grant for that rule is "enforce"
#   canary-enforce in the lint   <=> latest ledger grant is "canary-enforce" with the SAME repos set
#                                     (a widened/changed repo scope needs its own new grant)
# => a new rule id with no ledger record CANNOT be enforce/canary-enforce (must enter as shadow),
#    and any enforcing rule MUST carry a grandfather/promote record. This runs inside the #873
#    brake, which advance-major-tag.sh already invokes before any v1 fleet-blast.
prov_out="$(python3 - "$lint_py" "$severity_extract_py" "$REPO_ROOT/frameworks/gates/rule-promotions.jsonl" <<'PROVCHECK'
import json, sys
lint_py, extractor_py, ledger = sys.argv[1], sys.argv[2], sys.argv[3]
exec(open(extractor_py).read())
src = open(lint_py).read()
sev = extract_severity_dict(src)
grant = {}  # rule_id -> latest full grant record (append-only ledger is chronological; last line wins)
try:
    for line in open(ledger):
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        grant[rec["rule_id"]] = rec
except FileNotFoundError:
    sys.exit(f"provenance ledger not found: {ledger}")
problems = []
for rid, s in sorted(sev.items(), key=lambda kv: kv[0]):
    g = grant.get(rid)
    g_sev = g.get("severity") if g else None
    if s == "enforce" and g_sev != "enforce":
        problems.append(f"{rid} is 'enforce' in the lint but has no current enforce grant in the ledger "
                        f"(grant={g_sev!r}) — enforce rules MUST carry a grandfather/promote record")
    elif isinstance(s, dict) and s.get("mode") == "canary-enforce":
        if g_sev != "canary-enforce":
            problems.append(f"{rid} is canary-enforce in the lint but has no current canary-enforce grant "
                            f"in the ledger (grant={g_sev!r}) — canary-enforce rules MUST carry a promote record")
        else:
            lint_repos = sorted(s.get("repos") or [])
            ledger_repos = sorted((g or {}).get("repos") or [])
            if lint_repos != ledger_repos:
                problems.append(f"{rid} canary-enforce repos {lint_repos} don't match the ledger grant's "
                                f"repos {ledger_repos} — a changed canary scope needs its own new grant")
    elif s == "shadow" and g_sev == "enforce":
        problems.append(f"{rid} is 'shadow' in the lint but the ledger's latest grant is 'enforce' — "
                        f"record the demotion via demote-rule.sh")
if problems:
    sys.exit("; ".join(problems))
enf = sorted(r for r, v in sev.items() if v == "enforce")
canary = sorted(r for r, v in sev.items() if isinstance(v, dict) and v.get("mode") == "canary-enforce")
print(f"enforce rules with ledger grants: {enf}; canary-enforce rules with ledger grants: {canary}")
PROVCHECK
)" && prov_rc=0 || prov_rc=$?
if [ "${prov_rc:-0}" -ne 0 ]; then
  echo "FAIL provenance: $prov_out"
  fail=1
else
  echo "PASS provenance ($prov_out)"
fi

for good in "$FIXTURES"/good-*.yml; do
  name="$(basename "$good")"
  set +e; out="$(run_lint "$good" 2>&1)"; rc=$?; set -e
  errs="$(printf '%s\n' "$out" | grep -c '^::error::' || true)"
  if [ "$rc" -ne 0 ] || [ "$errs" -ne 0 ]; then
    echo "FAIL $name: expected exit 0 / 0 violations, got exit=$rc violations=$errs"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  else
    echo "PASS $name (exit 0, 0 violations)"
  fi
done

# Parallel case/lookup instead of an associative array — bash 3.2 (macOS default) has none.
rule_marker() {
  case "$1" in
    bad-rule1-no-concurrency.yml)         echo "no 'concurrency:' block" ;;
    bad-rule2-reusable-cancel-true.yml)   echo "a cancel here fires across all callers" ;;
    bad-rule3-push-mg-no-exclude.yml)     echo "queue self-eviction risk #852" ;;
    bad-rule4-release-cancel-true.yml)    echo "never interrupt an in-flight publish" ;;
    bad-rule5-non-ubuntu-runner.yml)      echo "not in allowlist" ;;
    bad-rule5-blacksmith-malformed.yml)   echo "not in allowlist" ;;
    *) echo "" ;;
  esac
}

for bad in "$FIXTURES"/bad-rule*.yml; do
  name="$(basename "$bad")"
  marker="$(rule_marker "$name")"
  if [ -z "$marker" ]; then
    echo "FAIL $name: no expected marker registered in this test — add one to RULE_MARKER"
    fail=1
    continue
  fi
  set +e; out="$(run_lint "$bad" 2>&1)"; rc=$?; set -e
  errs="$(printf '%s\n' "$out" | grep -c '^::error::' || true)"
  if [ "$rc" -ne 1 ]; then
    echo "FAIL $name: expected exit 1, got exit=$rc"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
    continue
  fi
  if [ "$errs" -ne 1 ]; then
    echo "FAIL $name: expected exactly 1 ::error:: violation, got $errs"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
    continue
  fi
  if ! printf '%s\n' "$out" | grep -qF "$marker"; then
    echo "FAIL $name: expected ::error:: to mention '$marker'"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
    continue
  fi
  echo "PASS $name (exit 1, exactly rule's ::error:: fired: '$marker')"
done

if [ "$fail" = 0 ]; then
  echo "✓ workflow-policy self-test: all good/bad fixtures + the severity/provenance structure behave as expected against the DEPLOYED lint in $CHECKS_YML (shadow rules + canary routing: test-workflow-policy-shadow.sh)"
else
  echo "✗ workflow-policy self-test FAILED — a WAS rule (1-5) or the severity/provenance structure regressed" >&2
fi
exit "$fail"
