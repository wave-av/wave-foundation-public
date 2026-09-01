#!/usr/bin/env bash
# test-check-claude-config-workflow.sh — self-test for the WORKFLOW copy of the `.claude/`
# governance gate: the inline block in .github/workflows/checks.yml (job: claude-config), whose
# comments require it to stay behaviourally in sync with scripts/check-claude-config.sh.
#
# SPLIT OUT of test-check-claude-config.sh (which drills the SCRIPT copy) when the combined
# file outgrew the token-budget ratchet's per-file cap: one gate copy per drill file, same
# harness. When the gate changes, extend BOTH suites so the copies cannot drift apart; the
# case letters here (J..V, Z2) name which script-copy case each one mirrors.
#
# The inline block is extracted from checks.yml at run time, never re-typed (a re-typed copy is
# a third implementation — see test-secret-scan.sh), and runs under `bash -e`, matching
# GitHub's `/usr/bin/bash -e {0}`. Canary strings are assembled at runtime so this file never
# contains a credential shape or an absolute home path that the org's own gates would flag.
#
# Usage:  bash frameworks/gates/test-check-claude-config-workflow.sh
# Exit:   0 = every case behaved as specified · 1 = at least one case regressed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="$(cd "$HERE/../.." && pwd)/.github/workflows/checks.yml"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# Assembled at runtime so this file carries neither a credential shape nor a home-path literal.
canary="ghp_$(printf 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234')"
homedir="$(printf '/%s/%s/' Users alice)"

# new_repo <name> — a fresh git repo with one anchor file (the gate refuses an EMPTY tree by
# design, and most cases want a tree that is clean except for the fixture under test).
new_repo() {
  local d="$work/$1"
  git init -q -b main "$d"
  git -C "$d" config user.email drill@wave.online
  git -C "$d" config user.name drill
  printf 'anchor\n' > "$d/README.md"
  printf '%s' "$d"
}

echo "== the WORKFLOW copy — checks.yml's inline block must agree with the script =="

inline_block="$work/claude-config-inline.sh"
if [ ! -f "$WORKFLOW" ]; then
  fail "I  extract checks.yml inline block  -> workflow not found at $WORKFLOW"
elif ! python3 - "$WORKFLOW" "$inline_block" <<'PY'
import sys, yaml
wf, out = sys.argv[1], sys.argv[2]
steps = [s for j in yaml.safe_load(open(wf, encoding='utf-8'))['jobs'].values()
         for s in (j.get('steps') or []) if 'Governed .claude/ config gate' in str(s.get('name', ''))]
if len(steps) != 1:
    sys.exit(f"expected exactly 1 'Governed .claude/ config gate' step in checks.yml, found {len(steps)}")
open(out, 'w', encoding='utf-8').write(steps[0]['run'])
PY
then
  fail "I  extract checks.yml inline block  -> extraction failed"
else
  pass "I  extract checks.yml inline block"

  # expect_inline <case> <want_exit> <want_substring|-> <repo> — stages everything, runs the
  # extracted block. Substring check is [[ == *""* ]], not grep, for the pipefail/EPIPE reason
  # in test-secret-scan.sh.
  expect_inline() {
    local name="$1" want_exit="$2" want_text="$3" repo="$4" out rc
    git -C "$repo" add -A
    out="$(cd "$repo" && bash -e "$inline_block" 2>&1)"; rc=$?
    if [ "$rc" -ne "$want_exit" ]; then
      fail "$name — exit $rc, want $want_exit"
      printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
      return
    fi
    if [ "$want_text" != "-" ] && [[ "$out" != *"$want_text"* ]]; then
      fail "$name — exit $rc correct, but output never says '$want_text'"
      return
    fi
    pass "$name"
  }

  # J — the control: the copy must PASS a clean tree, or K-M measure a harness, not the gate.
  t="$(new_repo wf_j)"; mkdir -p "$t/.claude"
  printf 'model: opus\n' > "$t/.claude/settings.json"
  expect_inline "J  workflow: clean .claude/ file    -> clean" 0 "claude-config gate: clean" "$t"

  # K — dangling home-dir symlink: the workflow copy must refuse it too (mirrors D).
  t="$(new_repo wf_k)"; mkdir -p "$t/.claude"
  ln -s "${homedir}secret-config.json" "$t/.claude/link"
  expect_inline "K  workflow: dangling home link     -> violation" 1 "symlink target is a hardcoded absolute home path" "$t"

  # L — contents through a resolvable link stay scanned in the workflow copy (mirrors F).
  t="$(new_repo wf_l)"; mkdir -p "$t/.claude" "$t/shared"
  printf 'token: %s\n' "$canary" > "$t/shared/creds.yaml"
  ln -s "../shared/creds.yaml" "$t/.claude/link"
  expect_inline "L  workflow: link -> secret file    -> violation" 1 "secret-like credential" "$t"

  # M — the slash-less whole-.claude symlink reaches the workflow copy's symlink branch too
  # (mirrors G).
  t="$(new_repo wf_m)"
  ln -s "${homedir}dotfiles/claude" "$t/.claude"
  expect_inline "M  workflow: whole .claude symlink  -> violation" 1 "symlink target is a hardcoded absolute home path" "$t"

  # N — the in-repo directory redirect is traversed and scanned by the workflow copy too
  # (mirrors G2).
  t="$(new_repo wf_n)"; mkdir -p "$t/config/claude"
  printf 'path: %sdotfiles\n' "$homedir" > "$t/config/claude/settings.json"
  ln -s "config/claude" "$t/.claude"
  expect_inline "N  workflow: dir symlink, dirty     -> violation" 1 "hardcoded absolute home path" "$t"

  # O — and a clean directory dedupe stays legal in the workflow copy (mirrors G3).
  t="$(new_repo wf_o)"; mkdir -p "$t/.claude" "$t/plugin/skills/x"
  printf 'model: opus\n' > "$t/plugin/skills/x/SKILL.md"
  ln -s "../plugin/skills/x" "$t/.claude/skills-x"
  printf 'model: opus\n' > "$t/.claude/settings.json"
  expect_inline "O  workflow: dir symlink, clean     -> clean" 0 "claude-config gate: clean" "$t"

  # R — the workflow copy honours the allowlist through a directory link too, matched on the
  # repo-relative resolved path (mirrors G5).
  t="$(new_repo wf_r)"; mkdir -p "$t/.claude" "$t/plugin/skills/x" "$t/.github"
  printf 'path: %sdotfiles\n' "$homedir" > "$t/plugin/skills/x/SKILL.md"
  ln -s "../plugin/skills/x" "$t/.claude/skills-x"
  printf 'plugin/skills/x/SKILL.md\n' > "$t/.github/.claude-governance-allow"
  expect_inline "R  workflow: allowlisted via link   -> clean" 0 "claude-config gate: clean" "$t"

  # P: containment holds in the workflow copy too: an out-of-repo resolvable link is refused
  # (mirrors G4).
  t="$(new_repo wf_p)"; mkdir -p "$t/.claude"
  printf 'model: opus\n' > "$work/outside-p.txt"
  ln -s "../../outside-p.txt" "$t/.claude/link"
  expect_inline "P  workflow: link outside the repo   -> violation" 1 "resolves OUTSIDE the repository" "$t"

  # S — the workflow copy exempts a FILE link into staging/ too (mirrors G6b).
  t="$(new_repo wf_s)"; mkdir -p "$t/.claude" "$t/staging/harvest"
  printf 'path: %sdotfiles\n' "$homedir" > "$t/staging/harvest/notes.md"
  ln -s "../staging/harvest/notes.md" "$t/.claude/notes.md"
  expect_inline "S  workflow: file link -> staging/   -> clean" 0 "claude-config gate: clean" "$t"

  # T — the workflow copy refuses a dangling home-path link behind a directory redirect too
  # (mirrors G7): dangling-link enumeration and the target-string rules must not drift.
  t="$(new_repo wf_t)"; mkdir -p "$t/config/claude"
  ln -s "${homedir}secret-config.json" "$t/config/claude/link"
  ln -s "config/claude" "$t/.claude"
  expect_inline "T  workflow: dir link -> dangling home -> violation" 1 "symlink target is a hardcoded absolute home path" "$t"

  # T2 — exemptions reach a dangling link behind the redirect in the workflow copy too
  # (mirrors G7c): staging/ material with a broken home-path link stays exempt by PATH.
  t="$(new_repo wf_t2)"; mkdir -p "$t/staging/harvest"
  ln -s "${homedir}secret-config.json" "$t/staging/harvest/link"
  ln -s "staging/harvest" "$t/.claude"
  expect_inline "T2 workflow: staging dangling link   -> clean" 0 "claude-config gate: clean" "$t"

  # T3 — and the allowlist clears a dangling link, matched on the resolved spelling
  # (mirrors G7d).
  t="$(new_repo wf_t3)"; mkdir -p "$t/config/claude" "$t/.github"
  ln -s "${homedir}secret-config.json" "$t/config/claude/link"
  ln -s "config/claude" "$t/.claude"
  printf 'config/claude/link\n' > "$t/.github/.claude-governance-allow"
  expect_inline "T3 workflow: allowlisted dangling    -> clean" 0 "claude-config gate: clean" "$t"

  # T4 — the root-directory edge (mirrors G7e): a redirect resolving to the repo root itself
  # must still let the allowlist clear a dangling link there (rel must not stay absolute).
  t="$(new_repo wf_t4)"; mkdir -p "$t/.github"
  ln -s "${homedir}secret-config.json" "$t/broken"
  ln -s "." "$t/.claude"
  printf 'broken\n' > "$t/.github/.claude-governance-allow"
  expect_inline "T4 workflow: root redirect, allowed  -> clean" 0 "claude-config gate: clean" "$t"

  # U — the workflow copy prunes at the boundary too (mirrors G8): the escaping nested link is
  # refused at the boundary, and nothing beyond it is walked or named.
  t="$(new_repo wf_u)"; mkdir -p "$t/config/claude" "$work/outside-u"
  printf 'model: opus\n' > "$work/outside-u/private-notes-canary.txt"
  ln -s "../../../outside-u" "$t/config/claude/link"
  ln -s "config/claude" "$t/.claude"
  expect_inline "U  workflow: nested link escapes     -> violation" 1 "resolves OUTSIDE the repository" "$t"
  out="$(cd "$t" && git add -A && bash -e "$inline_block" 2>&1)"
  case "$out" in
    *private-notes-canary*) fail "U2 workflow: outside names never printed — descended past the boundary" ;;
    *)                      pass "U2 workflow: outside names never printed" ;;
  esac

  # V — link cycles terminate in the workflow copy too (mirrors G9).
  t="$(new_repo wf_v)"; mkdir -p "$t/config/claude"
  printf 'path: %sdotfiles\n' "$homedir" > "$t/config/claude/settings.json"
  ln -s "." "$t/config/claude/self"
  ln -s "config/claude" "$t/.claude"
  expect_inline "V  workflow: link cycle              -> violation" 1 "hardcoded absolute home path" "$t"

  # Z2 — the workflow copy's root guard fires outside a git repo too (mirrors Z; exit 1 there).
  nong="$work/not-a-repo-z2"; mkdir -p "$nong"
  out="$(cd "$nong" && bash -e "$inline_block" 2>&1)"; rc=$?
  if [ "$rc" -eq 1 ] && [[ "$out" == *"cannot resolve the repository root"* ]]; then
    pass "Z2 workflow: not a git repo         -> refused (exit 1)"
  else
    fail "Z2 workflow: not a git repo         -> refused (exit $rc, want 1)"
    printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
  fi
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "check-claude-config-workflow self-test: all cases pass"
  exit 0
fi
echo "check-claude-config-workflow self-test: $fails case(s) FAILED"
exit 1
