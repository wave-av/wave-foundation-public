#!/usr/bin/env bash
# test-secret-scan-exceptions.sh — key shapes, finding output and base-commit exceptions, for both
# copies of the secret-scan gate: scripts/secret-scan.sh and the inline step in checks.yml.
#
# Harness and fake values: lib/secret-scan-harness.sh.
#
# Usage:  bash frameworks/gates/test-secret-scan-exceptions.sh   (run by test-secret-scan.sh)
# Exit:   0 = every case behaved as specified · 1 = at least one case regressed.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/secret-scan-harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/secret-scan-harness.sh"

BK_GATE="$REPO/.buildkite/gates/checks.checks.01-secret-scan-fail-closed-allowlist-aware.gate"
fake_tail="$(printf 'Zq7%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
whsec_key="whsec_${fake_tail}"
svix_key="whsec_$(printf 'Zq+7/%.0s' 1 2 3 4 5)"
wk_key="wk_${fake_tail}"
wk_live_key="wk_live_${fake_tail}"
wk_dotted_key="wk_live_Zq7Zq7.${fake_tail}"

echo "== key shapes — each one is detected, and near misses are not =="

both "U1 whsec_ shape                     -> detected" 1 "do not commit credentials" "$(shape_tree u1 "const k = '$whsec_key';")"
both "U2 whsec_ base64 tail               -> detected" 1 "do not commit credentials" "$(shape_tree u2 "const k = '$svix_key';")"
both "U3 wk_ shape                        -> detected" 1 "do not commit credentials" "$(shape_tree u3 "Bearer $wk_key")"
both "U4 wk_live_ shape                   -> detected" 1 "do not commit credentials" "$(shape_tree u4 "Bearer $wk_live_key")"
both "U5 wk_ prefix.secret shape          -> detected" 1 "do not commit credentials" "$(shape_tree u5 "Bearer $wk_dotted_key")"
both "U6 wk_ at the start of a line       -> detected" 1 "do not commit credentials" "$(shape_tree u6 "$wk_key")"
# The controls for U1-U6: an identifier ending in `wk_`, a short fixture and a short placeholder pass.
both "U7 identifier ending in wk_         -> clean" 0 "secret-scan clean" "$(shape_tree u7 "hawk_${fake_tail}")"
both "U8 short wk_ fixture                -> clean" 0 "secret-scan clean" "$(shape_tree u8 "const k = 'wk_test_key_123';")"
both "U9 short whsec_ placeholder         -> clean" 0 "secret-scan clean" "$(shape_tree u9 "SECRET=whsec_xxxx")"

echo "== output — a finding is reported as file:line, never as the matched text =="

t="$(shape_tree v1 "const k = '$whsec_key'; // neighbouring-sentinel-text")"
both "V1 names file:line                  -> src/config.js:1" 1 "./src/config.js:1" "$t"
never_prints "V2 value is not printed" "$whsec_key" "$t"
never_prints "V3 rest of the line is not printed" "neighbouring-sentinel-text" "$t"
# A colon in the path must not change where the record is cut.
t="$work/v4"; mkdir -p "$t/src"; printf '%s\n' "const k = '$whsec_key';" > "$t/src/a:b.js"
both "V4 colon in a path                  -> names it" 1 "./src/a:b.js:1" "$t"
never_prints "V5 colon in a path, value not printed" "$whsec_key" "$t"
# The same for a shape the gate has always detected.
never_prints "V6 AKIA value is not printed" "$canary" "$(shape_tree v6 "key: $canary")"

echo "== exceptions — on a pull request they are read from the base commit =="

# W0 — exceptions already on the base keep working. Every W case below is only meaningful next to
# this one: a gate that fails every tree would pass them all.
t="$(pr_tree w0)"; on_pr "$(base_of "$t")"
both "W0 listed file + old pragma line    -> clean" 0 "secret-scan clean" "$t"

# W1 — a new finding, with the entry for it arriving in the same change.
t="$(pr_tree w1)"; on_pr "$(base_of "$t")"
printf 'const k = "%s";\n' "$canary" > "$t/src/new.js"
printf 'src/new.js\n' >> "$t/.github/.secret-allowlist"
both "W1 new entry in the same change     -> detected" 1 "./src/new.js:1" "$t"

# W2 — the same for the inline pragma.
t="$(pr_tree w2)"; on_pr "$(base_of "$t")"
printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$t/src/new.js"
both "W2 new pragma line                  -> detected" 1 "./src/new.js:1" "$t"

# W3 — a pragma line already on the base, edited: it is a new line.
t="$(pr_tree w3)"; on_pr "$(base_of "$t")"
printf 'const k = "%sX"; // pragma: allowlist secret\n' "$canary" > "$t/src/fixture.js"
both "W3 edited pragma line               -> detected" 1 "./src/fixture.js:1" "$t"

# W4 — an entry's text on a new line of an unlisted file is not a path match.
t="$(pr_tree w4)"; on_pr "$(base_of "$t")"
printf 'const k = "%s"; // docs/EXAMPLE.md\n' "$canary" > "$t/src/new.js"
both "W4 entry text on a new line         -> detected" 1 "./src/new.js:1" "$t"

# W5 — the exception file is scanned for lines that are new to it.
t="$(pr_tree w5)"; on_pr "$(base_of "$t")"
printf '# %s\n' "$canary" >> "$t/.github/.secret-allowlist"
both "W5 new key shape in the allowlist   -> detected" 1 "./.github/.secret-allowlist:3" "$t"

# W6 — only the exception file at its real path gets that treatment.
t="$(pr_tree w6)"; on_pr "$(base_of "$t")"
printf 'key: %s\n' "$canary" > "$t/src/.secret-allowlist"
both "W6 same file name elsewhere         -> detected" 1 "./src/.secret-allowlist:1" "$t"

# W7 — no allowlist on the base at all: one added by the change grants nothing yet.
t="$(pr_tree w7)"
git_t "$t" rm -q .github/.secret-allowlist docs/EXAMPLE.md
git_t "$t" commit -q -m drop
on_pr "$(base_of "$t")"
mkdir -p "$t/.github"
printf 'const k = "%s";\n' "$canary" > "$t/src/new.js"
printf 'src/new.js\n' > "$t/.github/.secret-allowlist"
both "W7 allowlist absent on the base     -> detected" 1 "./src/new.js:1" "$t"

# W8 — deleting the list removes every entry in it, and the base branch would fail the same way.
t="$(pr_tree w8)"; on_pr "$(base_of "$t")"
rm -f "$t/.github/.secret-allowlist"
both "W8 allowlist deleted by the change  -> detected" 1 "./docs/EXAMPLE.md:1" "$t"

# W9 — a pull request with no base sha has no exceptions, and says so.
t="$(pr_tree w9)"; on_pr ""
both "W9 pull request, base sha empty     -> detected" 1 "./docs/EXAMPLE.md:1" "$t"
both "W9 pull request, base sha empty     -> names it" 1 "base commit" "$t"

# W10 — a base sha the checkout does not hold is the same case.
t="$(pr_tree w10)"; on_pr "0123456789012345678901234567890123456789"
both "W10 pull request, base sha unknown  -> detected" 1 "./docs/EXAMPLE.md:1" "$t"

# W11 — the merge queue reads its own base variable.
t="$(pr_tree w11)"; on_queue "$(base_of "$t")"
both "W11 merge queue, old exceptions     -> clean" 0 "secret-scan clean" "$t"
printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$t/src/new.js"
both "W11 merge queue, new pragma line    -> detected" 1 "./src/new.js:1" "$t"

# W12 — a push proposes nothing to read a base for: the tree is the state being checked.
t="$(pr_tree w12)"; gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=push)
printf 'const k = "%s";\n' "$canary" > "$t/src/new.js"
printf 'src/new.js\n' >> "$t/.github/.secret-allowlist"
both "W12 push, tree allowlist            -> clean" 0 "secret-scan clean" "$t"

# W13 — the format check still reads the working copy, so a change learns its file is malformed.
t="$(pr_tree w13)"; on_pr "$(base_of "$t")"
printf '# only comments now\n' > "$t/.github/.secret-allowlist"
both "W13 malformed working copy          -> rejected" 1 "ZERO patterns" "$t"
gate_env=("${no_ci_env[@]}")

echo "== listed paths — an entry names a whole path, or a directory on the base, never a substring =="

# Y1-Y3 — the three ways a new file can hold an entry's text in its path. The entry is docs/EXAMPLE.md.
t="$(pr_tree y1)"; on_pr "$(base_of "$t")"
plant "$t" src/docs/EXAMPLE.md-real.ts
both "Y1 path contains an entry           -> detected" 1 "./src/docs/EXAMPLE.md-real.ts:1" "$t"

t="$(pr_tree y2)"; on_pr "$(base_of "$t")"
plant "$t" docs/EXAMPLE.md-real.ts
both "Y2 entry plus a suffix              -> detected" 1 "./docs/EXAMPLE.md-real.ts:1" "$t"

t="$(pr_tree y3)"; on_pr "$(base_of "$t")"
plant "$t" src/docs/EXAMPLE.md
both "Y3 entry as a later path component  -> detected" 1 "./src/docs/EXAMPLE.md:1" "$t"

# Y4-Y5 — the controls: what an entry is for still works, so Y1-Y3 are not a gate that fails every tree.
t="$(pr_tree y4)"; on_pr "$(base_of "$t")"
both "Y4 exact entry                      -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y5 fixtures fixtures/old.md)"; on_pr "$(base_of "$t")"
plant "$t" fixtures/sub/new.js
both "Y5 under a directory entry          -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y6 fixtures/ fixtures/old.md)"; on_pr "$(base_of "$t")"
plant "$t" fixtures/new.js
both "Y6 under a directory entry with /   -> clean" 0 "secret-scan clean" "$t"

# Y7-Y8 — a directory entry has the same edges as a file entry.
t="$(pr_tree_with y7 fixtures fixtures/old.md)"; on_pr "$(base_of "$t")"
plant "$t" fixtures-real/new.js
both "Y7 sibling of a directory entry     -> detected" 1 "./fixtures-real/new.js:1" "$t"

t="$(pr_tree_with y8 fixtures fixtures/old.md)"; on_pr "$(base_of "$t")"
plant "$t" src/fixtures/new.js
both "Y8 directory entry, later component -> detected" 1 "./src/fixtures/new.js:1" "$t"

# Y9-Y10 — what counts as a directory is read from the base, so the change cannot make one.
t="$(pr_tree y9)"; on_pr "$(base_of "$t")"
rm -f "$t/docs/EXAMPLE.md"
plant "$t" docs/EXAMPLE.md/new.js
both "Y9 file entry turned into a directory -> detected" 1 "./docs/EXAMPLE.md/new.js:1" "$t"

t="$(pr_tree_with y10 later)"; on_pr "$(base_of "$t")"
plant "$t" later/new.js
both "Y10 entry is a directory only in the change -> detected" 1 "./later/new.js:1" "$t"

# Y12 — a file name is compared whole, so an entry on its own line of a name is not a match.
t="$(pr_tree y12)"; on_pr "$(base_of "$t")"
plant "$t" "$(printf 'src/x\ndocs/EXAMPLE.md')"
both "Y12 entry after a newline in a name -> detected" 1 "./src/x?docs/EXAMPLE.md:1" "$t"

# Y13-Y14 — the separate line-text exception is unchanged: it holds for a line unchanged from the base.
t="$(pr_tree_with y13 vetted-shape-note)"
printf 'const k = "%s"; // vetted-shape-note\n' "$canary" > "$t/src/old.js"
git_t "$t" add -A; git_t "$t" commit -q -m line
on_pr "$(base_of "$t")"
both "Y13 entry text on a base line       -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y14 vetted-shape-note)"; on_pr "$(base_of "$t")"
printf 'const k = "%s"; // vetted-shape-note\n' "$canary" > "$t/src/old.js"
both "Y14 entry text on a new line        -> detected" 1 "./src/old.js:1" "$t"

# Y15-Y20 — with no base to read, the tree decides what is a directory, under the same matching rules.
gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=push)
t="$(pr_tree y15)"; plant "$t" src/docs/EXAMPLE.md-real.ts
both "Y15 tree: path contains an entry    -> detected" 1 "./src/docs/EXAMPLE.md-real.ts:1" "$t"

t="$(pr_tree y16)"; plant "$t" docs/EXAMPLE.md-real.ts
both "Y16 tree: entry plus a suffix       -> detected" 1 "./docs/EXAMPLE.md-real.ts:1" "$t"

t="$(pr_tree y17)"; plant "$t" src/docs/EXAMPLE.md
both "Y17 tree: entry as a later component -> detected" 1 "./src/docs/EXAMPLE.md:1" "$t"

t="$(pr_tree y18)"
both "Y18 tree: exact entry               -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y19 fixtures)"; plant "$t" fixtures/sub/new.js
both "Y19 tree: under a directory entry   -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with y20 fixtures)"; plant "$t" fixtures-real/new.js
both "Y20 tree: sibling of a directory    -> detected" 1 "./fixtures-real/new.js:1" "$t"
gate_env=("${no_ci_env[@]}")

echo "== wiring — the CI steps pass the base variables, and the Buildkite copy matches =="

if python3 - "$WORKFLOW" "$REPO/.github/workflows/self-check.yml" <<'PY'
import sys, yaml
for wf in sys.argv[1:]:
    steps = [s for j in yaml.safe_load(open(wf, encoding='utf-8'))['jobs'].values()
             for s in (j.get('steps') or []) if str(s.get('name', '')).startswith('Secret scan')]
    if len(steps) != 1 or not {'PR_BASE_SHA', 'PR_HEAD_SHA', 'MERGE_BASE_SHA'} <= set(steps[0].get('env') or {}):
        sys.exit(f"{wf}: the Secret scan step does not set PR_BASE_SHA, PR_HEAD_SHA and MERGE_BASE_SHA")
PY
then pass "X1 workflow steps set the base variables"
else fail "X1 workflow steps set the base variables"
fi

# The .gate file is six header lines plus the workflow step's run body, unchanged.
if [ "$(tail -n +7 "$BK_GATE")" = "$(cat "$inline_block")" ]; then
  pass "X2 Buildkite gate equals the workflow step"
else
  fail "X2 Buildkite gate equals the workflow step"
fi

finish "secret-scan exceptions"
