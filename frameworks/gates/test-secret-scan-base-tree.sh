#!/usr/bin/env bash
# test-secret-scan-base-tree.sh — which commit a pull request's exceptions come from, and that an
# exception the change removes stops applying, for both copies of the secret-scan gate.
#
# A pull request runs on GitHub's merge commit: its first parent is the base branch as merged, its
# second is the pull request's head. PR_BASE_SHA can be older than that first parent. Buildkite runs
# on the head itself, with PR_BASE_SHA at the base branch's tip, which can be ahead of the fork point.
#
# Harness and fake values: lib/secret-scan-harness.sh.
#
# Usage:  bash frameworks/gates/test-secret-scan-base-tree.sh   (run by test-secret-scan.sh)
# Exit:   0 = every case behaved as specified · 1 = at least one case regressed.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/secret-scan-harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/secret-scan-harness.sh"

on_pr_merge() { gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=pull_request PR_BASE_SHA="$1" PR_HEAD_SHA="$2"); }

commit_all() {
  git_t "$1" add -A
  git_t "$1" commit -q -m "$2"
}

# branch_off <tree> [<file>] — the pull request's own commit, with a pragma-tagged key line in <file>
# if named, then back to the base, detached, ready for a peer's commits. Sets pr_base and pr_head.
pr_base="" pr_head=""
branch_off() {
  pr_base="$(base_of "$1")"
  git_t "$1" checkout -q -b pr
  printf 'changed\n' > "$1/src/app.js"
  if [ -n "${2:-}" ]; then
    printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$1/$2"
  fi
  commit_all "$1" pr
  pr_head="$(base_of "$1")"
  git_t "$1" checkout -q "$pr_base"
}

# github_merge <tree> — what refs/pull/N/merge holds: the base branch first, the pull request second.
github_merge() { git_t "$1" merge -q --no-ff --no-edit "$pr_head"; }

# peer_pragma <tree> — a peer's reviewed pragma line lands on the base branch.
peer_pragma() {
  printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$1/src/peer.js"
  commit_all "$1" peer
}

echo "== merge commit — exceptions come from the base branch as merged, not the frozen PR_BASE_SHA =="

# MC0 is what makes the rest mean anything: the tree really has the shape GitHub checks out.
t="$(pr_tree mc1)"; branch_off "$t"; peer_pragma "$t"; github_merge "$t"
if [ "$(git -C "$t" rev-parse 'HEAD^2')" = "$pr_head" ] && [ "$(git -C "$t" rev-parse 'HEAD^1')" != "$pr_base" ]; then
  pass "MC0 the tree is a merge commit, base branch first"
else
  fail "MC0 the tree is a merge commit, base branch first"
fi

on_pr_merge "$pr_base" "$pr_head"
both "MC1 peer's pragma line, file untouched  -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree mc2)"; branch_off "$t"
plant "$t" src/peer.js
printf 'src/peer.js\n' >> "$t/.github/.secret-allowlist"
commit_all "$t" peer; github_merge "$t"
on_pr_merge "$pr_base" "$pr_head"
both "MC2 peer's entry and listed file        -> clean" 0 "secret-scan clean" "$t"

# MC3-MC4 — the correction reads the base branch, so what the pull request adds still has to wait.
t="$(pr_tree mc3)"; branch_off "$t" src/own.js; peer_pragma "$t"; github_merge "$t"
on_pr_merge "$pr_base" "$pr_head"
both "MC3 the change's own pragma line        -> detected" 1 "./src/own.js:1" "$t"

t="$(pr_tree mc4)"
pr_base="$(base_of "$t")"
git_t "$t" checkout -q -b pr
plant "$t" src/own.js
printf 'src/own.js\n' >> "$t/.github/.secret-allowlist"
commit_all "$t" pr; pr_head="$(base_of "$t")"
git_t "$t" checkout -q "$pr_base"; peer_pragma "$t"; github_merge "$t"
on_pr_merge "$pr_base" "$pr_head"
both "MC4 the change's own entry              -> detected" 1 "./src/own.js:1" "$t"

# MC5 — an author merging the base into their own branch has the parents the other way round: the first
# is their branch. Going by "HEAD has two parents" would take the pull request as its own base.
t="$(pr_tree mc5)"; branch_off "$t" src/own.js; peer_pragma "$t"
peer_tip="$(base_of "$t")"
git_t "$t" checkout -q pr
git_t "$t" merge -q --no-ff --no-edit "$peer_tip"
on_pr_merge "$peer_tip" "$(base_of "$t")"
both "MC5 author's own merge of the base      -> detected" 1 "./src/own.js:1" "$t"

# MC6-MC7 — only a second parent equal to the pull request's head moves the base. A merge queue run
# has no head variable, and its base is the one it was given.
t="$(pr_tree mc6)"; branch_off "$t"; peer_pragma "$t"; github_merge "$t"
on_queue "$pr_base"
both "MC6 merge queue, frozen base            -> detected" 1 "./src/peer.js:1" "$t"

on_pr_merge "$pr_base" 0123456789012345678901234567890123456789
both "MC7 second parent is not the head       -> detected" 1 "./src/peer.js:1" "$t"

# MC8 — no merge commit at all and a base that has not moved: the HC cases below move it.
t="$(pr_tree mc8)"; branch_off "$t"; git_t "$t" checkout -q pr
on_pr_merge "$pr_base" "$pr_head"
both "MC8 head checked out, old exceptions    -> clean" 0 "secret-scan clean" "$t"
printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$t/src/own.js"
both "MC8 head checked out, new pragma line   -> detected" 1 "./src/own.js:1" "$t"

# MC9 — the frozen sha need not be fetched for the merge commit's own first parent to be read.
t="$(pr_tree mc9)"; branch_off "$t"; peer_pragma "$t"; github_merge "$t"
on_pr_merge 0123456789012345678901234567890123456789 "$pr_head"
both "MC9 frozen base not in the checkout     -> clean" 0 "secret-scan clean" "$t"

echo "== head checkout — exceptions come from the fork point, not the base branch's tip =="

# on_head <tree> — from the base branch's tip, onto the pull request's head, the way
# .buildkite/scripts/lib/common.sh runs: HEAD is the head, PR_BASE_SHA is origin/<base>.
pr_tip=""
on_head() {
  pr_tip="$(base_of "$1")"
  git_t "$1" checkout -q pr
  on_pr_merge "$pr_tip" "$pr_head"
}

# peer_edit <tree> — a peer changes the text of the base's pragma line, in a file the change never touched.
peer_edit() {
  printf 'const k = "%s"; // pragma: allowlist secret, reworded\n' "$canary" > "$1/src/fixture.js"
  commit_all "$1" peer
}

# HC0 is what makes the rest mean anything: the base branch really has moved past the fork point.
t="$(pr_tree hc1)"; branch_off "$t"; peer_pragma "$t"; on_head "$t"
if [ "$(base_of "$t")" = "$pr_head" ] && [ "$pr_tip" != "$pr_base" ] && [ "$(git -C "$t" merge-base HEAD "$pr_tip")" = "$pr_base" ]; then
  pass "HC0 HEAD is the head, forked from the old base"
else
  fail "HC0 HEAD is the head, forked from the old base"
fi
both "HC1 peer adds a pragma line elsewhere   -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree hc2)"; branch_off "$t"
plant "$t" src/peer.js
printf 'src/peer.js\n' >> "$t/.github/.secret-allowlist"
commit_all "$t" peer; on_head "$t"
both "HC2 peer adds an entry and its file     -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree hc3)"; branch_off "$t"; peer_edit "$t"; on_head "$t"
both "HC3 peer edits a pragma line            -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree hc4)"; branch_off "$t"
rm -f "$t/src/fixture.js"
commit_all "$t" peer; on_head "$t"
both "HC4 peer deletes a pragma line's file   -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree hc5)"; branch_off "$t"
printf '# exceptions\n' > "$t/.github/.secret-allowlist"
rm -f "$t/docs/EXAMPLE.md"
commit_all "$t" peer; on_head "$t"
both "HC5 peer deletes an entry and its file  -> clean" 0 "secret-scan clean" "$t"

# HC6-HC10 — the fork point is on the base branch, so what the change adds still has to wait, and a
# peer landing the same thing first does not make it reviewed here.
t="$(pr_tree hc6)"; branch_off "$t" src/own.js; peer_edit "$t"; on_head "$t"
both "HC6 the change's own pragma line        -> detected" 1 "./src/own.js:1" "$t"

t="$(pr_tree hc7)"; branch_off "$t"
git_t "$t" checkout -q pr
printf 'const k = "%s"; // pragma: allowlist secret, own edit\n' "$canary" > "$t/src/fixture.js"
commit_all "$t" own; pr_head="$(base_of "$t")"
git_t "$t" checkout -q "$pr_base"; peer_pragma "$t"; on_head "$t"
both "HC7 the change's own edit of a line     -> detected" 1 "./src/fixture.js:1" "$t"

t="$(pr_tree hc8)"; branch_off "$t" src/own.js
printf 'const k = "%s"; // pragma: allowlist secret\n' "$canary" > "$t/src/own.js"
commit_all "$t" peer; on_head "$t"
both "HC8 own line, a peer landed the same    -> detected" 1 "./src/own.js:1" "$t"

t="$(pr_tree hc9)"
pr_base="$(base_of "$t")"
git_t "$t" checkout -q -b pr
plant "$t" src/own.js
printf 'src/own.js\n' >> "$t/.github/.secret-allowlist"
commit_all "$t" pr; pr_head="$(base_of "$t")"
git_t "$t" checkout -q "$pr_base"
printf 'src/own.js\n' >> "$t/.github/.secret-allowlist"
commit_all "$t" peer; on_head "$t"
both "HC9 own entry, a peer landed the same   -> detected" 1 "./src/own.js:1" "$t"

# HC10 — an author who merged an older base into their branch forks from what they merged.
t="$(pr_tree hc10)"; branch_off "$t" src/own.js; peer_pragma "$t"
merged_tip="$(base_of "$t")"
git_t "$t" checkout -q pr; git_t "$t" merge -q --no-ff --no-edit "$merged_tip"; pr_head="$(base_of "$t")"
git_t "$t" checkout -q "$merged_tip"; peer_edit "$t"; on_head "$t"
both "HC10 author's merge, then a peer's edit  -> own line only" 1 "./src/own.js:1" "$t"
if out="$(run_script "$t")"; [[ "$out" != *"./src/fixture.js:1"* ]]; then
  pass "HC10 the peer's edit is not reported [script]"
else
  fail "HC10 the peer's edit is not reported [script]"
fi
if out="$(run_inline "$t")"; [[ "$out" != *"./src/fixture.js:1"* ]]; then
  pass "HC10 the peer's edit is not reported [workflow]"
else
  fail "HC10 the peer's edit is not reported [workflow]"
fi

# HC11 — HEAD is neither the head nor its merge commit, so the base is the one it was given.
t="$(pr_tree hc11)"; branch_off "$t"; peer_edit "$t"; on_head "$t"
on_pr_merge "$pr_tip" 0123456789012345678901234567890123456789
both "HC11 HEAD is not the head, base as given -> detected" 1 "./src/fixture.js:1" "$t"

# HC12-HC13 — a shallow clone holds both commits and no history joining them. No fork point means no
# exceptions, so every exception in the tree is reported, and the base's tip is never used instead.
t="$(pr_tree hc12)"; branch_off "$t"; peer_edit "$t"
git_t "$t" branch tip
tip_sha="$(base_of "$t")"
shallow="$work/hc12-shallow"
git_t "$work" clone -q --depth 1 --branch pr "file://$t" "$shallow"
git_t "$shallow" fetch -q --depth 1 origin tip:refs/remotes/origin/tip
if [ "$(base_of "$shallow")" = "$pr_head" ] && git -C "$shallow" cat-file -e "$tip_sha^{commit}" 2>/dev/null &&
  ! git -C "$shallow" merge-base HEAD "$tip_sha" >/dev/null 2>&1; then
  pass "HC12 the shallow clone has both commits and no merge base"
else
  fail "HC12 the shallow clone has both commits and no merge base"
fi
on_pr_merge "$tip_sha" "$pr_head"
both "HC12 no merge base, pragma line         -> detected" 1 "./src/fixture.js:1" "$shallow"
both "HC12 no merge base, listed file         -> detected" 1 "./docs/EXAMPLE.md:1" "$shallow"
both "HC12 no merge base                      -> warns" 1 "::warning::secret-scan: this change has no base commit available" "$shallow"

t="$(pr_tree hc13)"; branch_off "$t"; git_t "$t" checkout -q pr
on_pr_merge 0123456789012345678901234567890123456789 "$pr_head"
both "HC13 base not in the checkout           -> detected" 1 "./src/fixture.js:1" "$t"
both "HC13 base not in the checkout           -> warns" 1 "::warning::secret-scan: this change has no base commit available" "$t"

echo "== removed exceptions — an entry holds only if it is on the base and still in the tree =="

# RX0 — the control: the base's entries, and the same list in the tree, in another order.
t="$(pr_tree_with rx0 kept.md kept.md)"; on_pr "$(base_of "$t")"
printf 'kept.md\n# exceptions\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
both "RX0 same entries, reordered             -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with rx1 kept.md kept.md)"; on_pr "$(base_of "$t")"
printf '# exceptions\nkept.md\n' > "$t/.github/.secret-allowlist"
both "RX1 file entry removed, file stays      -> detected" 1 "./docs/EXAMPLE.md:1" "$t"
# A push reads the tree, so this is the result the base branch would get once the change merged.
gate_env=("${no_ci_env[@]}" GITHUB_EVENT_NAME=push)
both "RX1 the same tree on a push             -> detected" 1 "./docs/EXAMPLE.md:1" "$t"

# RX2 — the burndown the rule is for: the entry and what it excused go together.
t="$(pr_tree_with rx2 kept.md kept.md)"; on_pr "$(base_of "$t")"
printf '# exceptions\nkept.md\n' > "$t/.github/.secret-allowlist"
rm -f "$t/docs/EXAMPLE.md"
both "RX2 entry and file both removed         -> clean" 0 "secret-scan clean" "$t"

t="$(pr_tree_with rx3 fixtures fixtures/old.md)"
plant "$t" fixtures/key.js; commit_all "$t" key; on_pr "$(base_of "$t")"
printf '# exceptions\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
both "RX3 directory entry removed             -> detected" 1 "./fixtures/key.js:1" "$t"

t="$(pr_tree_with rx4 vetted-shape-note)"
printf 'const k = "%s"; // vetted-shape-note\n' "$canary" > "$t/src/old.js"
commit_all "$t" line; on_pr "$(base_of "$t")"
printf '# exceptions\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
both "RX4 line-text entry removed             -> detected" 1 "./src/old.js:1" "$t"

t="$(pr_tree_with rx5 src/old.js:1)"
plant "$t" src/old.js; commit_all "$t" line; on_pr "$(base_of "$t")"
printf '# exceptions\ndocs/EXAMPLE.md\n' > "$t/.github/.secret-allowlist"
both "RX5 path:line entry removed             -> detected" 1 "./src/old.js:1" "$t"

# RX6-RX7 — identical means the whole line: commented out or reworded is removed.
t="$(pr_tree_with rx6 kept.md kept.md)"; on_pr "$(base_of "$t")"
printf '# docs/EXAMPLE.md\nkept.md\n' > "$t/.github/.secret-allowlist"
both "RX6 entry commented out                 -> detected" 1 "./docs/EXAMPLE.md:1" "$t"

t="$(pr_tree_with rx7 kept.md kept.md)"; on_pr "$(base_of "$t")"
printf 'docs/EXAMPLE.md/\nkept.md\n' > "$t/.github/.secret-allowlist"
both "RX7 entry reworded                      -> detected" 1 "./docs/EXAMPLE.md:1" "$t"

t="$(pr_tree_with rx7a kept.md kept.md)"; on_pr "$(base_of "$t")"
printf 'docs/EXAMPLE\nkept.md\n' > "$t/.github/.secret-allowlist"
both "RX7a entry cut to a substring           -> detected" 1 "./docs/EXAMPLE.md:1" "$t"

# RX8 — a blank line in the tree's copy must not read as a pattern that keeps every base entry. The
# script's format check reaches it first; the workflow copy has to get it right on its own.
t="$(pr_tree_with rx8 kept.md kept.md)"; on_pr "$(base_of "$t")"
printf '\nkept.md\n' > "$t/.github/.secret-allowlist"
check_one "RX8 entry removed, blank line left [script]" run_script 1 "blank or whitespace-only" "$t"
check_one "RX8 entry removed, blank line left [workflow]" run_inline 1 "./docs/EXAMPLE.md:1" "$t"

# RX9 — both changes together: a peer's new entry holds, the entry this change removes does not.
t="$(pr_tree_with rx9 kept.md kept.md)"
pr_base="$(base_of "$t")"
git_t "$t" checkout -q -b pr
printf '# exceptions\nkept.md\n' > "$t/.github/.secret-allowlist"
commit_all "$t" pr; pr_head="$(base_of "$t")"
git_t "$t" checkout -q "$pr_base"
plant "$t" src/peer.js
printf 'src/peer.js\n' >> "$t/.github/.secret-allowlist"
commit_all "$t" peer; github_merge "$t"
on_pr_merge "$pr_base" "$pr_head"
both "RX9 merge commit, entry removed         -> detected" 1 "./docs/EXAMPLE.md:1" "$t"
if out="$(run_script "$t")"; [[ "$out" != *"./src/peer.js:1"* ]]; then
  pass "RX9 merge commit, peer's entry still holds [script]"
else
  fail "RX9 merge commit, peer's entry still holds [script]"
fi
if out="$(run_inline "$t")"; [[ "$out" != *"./src/peer.js:1"* ]]; then
  pass "RX9 merge commit, peer's entry still holds [workflow]"
else
  fail "RX9 merge commit, peer's entry still holds [workflow]"
fi

# RX10 — the merge queue reads its own variable and takes the same rule.
t="$(pr_tree_with rx10 kept.md kept.md)"; on_queue "$(base_of "$t")"
printf '# exceptions\nkept.md\n' > "$t/.github/.secret-allowlist"
both "RX10 merge queue, entry removed         -> detected" 1 "./docs/EXAMPLE.md:1" "$t"
gate_env=("${no_ci_env[@]}")

finish "secret-scan base and tree"
