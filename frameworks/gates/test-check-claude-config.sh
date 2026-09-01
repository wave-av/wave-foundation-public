#!/usr/bin/env bash
# test-check-claude-config.sh — self-test for the SCRIPT copy of the `.claude/` governance
# gate: scripts/check-claude-config.sh. The gate's other copy, the inline block in
# .github/workflows/checks.yml (job: claude-config), is drilled by the sibling
# test-check-claude-config-workflow.sh (split out when the combined file outgrew the
# token-budget ratchet's per-file cap). The two copies must stay behaviourally in sync: when
# the gate changes, extend BOTH suites — the workflow drill's case letters name which case
# here each one mirrors.
#
# Written when the gate's default flipped ON fleet-wide (enforce_claude_config true): a gate being
# armed everywhere in the same PR that reshaped its symlink handling deserves a drill pinning that
# handling. Cases cover the two fail-open shapes the reshape closed — a dangling symlink whose
# TARGET STRING violates the rules, and a whole `.claude` directory replaced by a symlink (a
# slash-less tracked path the old scope filter never visited) — plus the coverage that must NOT
# regress: contents reached THROUGH a resolvable link are still scanned.
#
# Every case builds a throwaway GIT repo under mktemp (the gate reads `git ls-files`) and runs the
# REAL gate against it. Canary strings are assembled at runtime so this file never contains a
# credential shape or an absolute home path that the org's own gates would flag.
#
# Usage:  bash frameworks/gates/test-check-claude-config.sh
# Exit:   0 = every case behaved as specified · 1 = at least one case regressed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../scripts/check-claude-config.sh"
[ -f "$GATE" ] || { echo "error: $GATE not found" >&2; exit 1; }
GATE="$(cd "$(dirname "$GATE")" && pwd)/$(basename "$GATE")"

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

# expect <case> <want_exit> <want_substring|-> <repo> — stages everything, runs the gate.
# Substring check is [[ == *""* ]], not grep, for the pipefail/EPIPE reason in test-secret-scan.sh.
expect() {
  local name="$1" want_exit="$2" want_text="$3" repo="$4" out rc
  git -C "$repo" add -A
  out="$(cd "$repo" && bash "$GATE" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want_exit" ]; then
    fail "$name — exit $rc, want $want_exit"
    printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
    return
  fi
  if [ "$want_text" != "-" ] && [[ "$out" != *"$want_text"* ]]; then
    fail "$name — exit $rc correct, but output never says '$want_text'"
    printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
    return
  fi
  pass "$name"
}

echo "== script copy — scripts/check-claude-config.sh =="

# A — the common case: a clean tracked .claude/ file.
t="$(new_repo a)"; mkdir -p "$t/.claude"
printf 'model: opus\n' > "$t/.claude/settings.json"
expect "A  clean .claude/ file              -> clean" 0 "claude-config gate: clean" "$t"

# B — hardcoded home path in file CONTENTS.
t="$(new_repo b)"; mkdir -p "$t/.claude"
printf 'path: %sdotfiles\n' "$homedir" > "$t/.claude/settings.json"
expect "B  home path in contents           -> violation" 1 "hardcoded absolute home path" "$t"

# C — materialized secret in file contents, and the value must be REDACTED in the output.
t="$(new_repo c)"; mkdir -p "$t/.claude"
printf 'token: %s\n' "$canary" > "$t/.claude/settings.json"
expect "C  secret in contents              -> violation" 1 "secret-like credential" "$t"
out="$(cd "$t" && git add -A && bash "$GATE" 2>&1)"
case "$out" in
  *"$canary"*) fail "C2 secret value REDACTED in output — the canary leaked" ;;
  *)           pass "C2 secret value REDACTED in output" ;;
esac

# D — THE FIRST FAIL-OPEN THIS PINS: a dangling symlink whose target string is a home path was
# skipped by `[ -f ]` (which FOLLOWS links) while the gate printed clean.
t="$(new_repo d)"; mkdir -p "$t/.claude"
ln -s "${homedir}secret-config.json" "$t/.claude/link"
expect "D  dangling link -> home dir       -> violation" 1 "symlink target is a hardcoded absolute home path" "$t"

# E — a dangling link with a benign relative target is NOT a violation.
t="$(new_repo e)"; mkdir -p "$t/.claude"
ln -s "shared/missing-but-benign" "$t/.claude/link"
expect "E  dangling link, benign target    -> clean" 0 "claude-config gate: clean" "$t"

# F — the coverage that must NOT regress: contents reached THROUGH a resolvable link are scanned,
# even when the target sits OUTSIDE .claude/** (the loop filter would never visit it directly).
t="$(new_repo f)"; mkdir -p "$t/.claude" "$t/shared"
printf 'token: %s\n' "$canary" > "$t/shared/creds.yaml"
ln -s "../shared/creds.yaml" "$t/.claude/link"
expect "F  link -> out-of-scope secret     -> violation" 1 "secret-like credential" "$t"

# G — THE SECOND FAIL-OPEN: the whole .claude directory replaced by a symlink. Its tracked path is
# the slash-less `.claude`, which the old scope filter (`.claude/*`) never matched.
t="$(new_repo g)"
ln -s "${homedir}dotfiles/claude" "$t/.claude"
expect "G  whole .claude is a home symlink -> violation" 1 "symlink target is a hardcoded absolute home path" "$t"

# G2 — THE THIRD FAIL-OPEN (Devin, PR #1163): .claude symlinked to an in-repo relative DIRECTORY.
# The target string matches neither regex, `-f` is false (it resolves to a directory), so the old
# code continued and printed clean while the real config lived at paths the scope filter never
# visits. The gate must traverse the link and scan what it finds.
t="$(new_repo g2)"; mkdir -p "$t/config/claude"
printf 'path: %sdotfiles\n' "$homedir" > "$t/config/claude/settings.json"
ln -s "config/claude" "$t/.claude"
expect "G2 dir symlink -> dirty contents  -> violation" 1 "hardcoded absolute home path" "$t"

# G3 — the flip side (Devin, PR #1163): a directory symlink is not a violation per se. A benign
# in-repo dedupe (.claude/skills-x -> ../plugin/skills/x, one level up from .claude/) must stay
# legal when its contents pass both rules; hard-failing every directory link would punish exactly
# that shape fleet-wide.
t="$(new_repo g3)"; mkdir -p "$t/.claude" "$t/plugin/skills/x"
printf 'model: opus\n' > "$t/plugin/skills/x/SKILL.md"
ln -s "../plugin/skills/x" "$t/.claude/skills-x"
printf 'model: opus\n' > "$t/.claude/settings.json"
expect "G3 dir symlink -> clean contents  -> clean" 0 "claude-config gate: clean" "$t"

# G5 — EXEMPTIONS THROUGH A LINK (Devin, PR #1163): a file reached through a directory symlink
# must honour the vetted allowlist exactly like a directly-scanned file, matched on its
# REPO-RELATIVE RESOLVED path (the real file's tracked spelling), or an allowed path becomes
# un-exemptable the moment a dedupe link fronts it.
t="$(new_repo g5)"; mkdir -p "$t/.claude" "$t/plugin/skills/x" "$t/.github"
printf 'path: %sdotfiles\n' "$homedir" > "$t/plugin/skills/x/SKILL.md"
ln -s "../plugin/skills/x" "$t/.claude/skills-x"
printf 'plugin/skills/x/SKILL.md\n' > "$t/.github/.claude-governance-allow"
expect "G5 dir link -> allowlisted file   -> clean" 0 "claude-config gate: clean" "$t"

# G5b — and the LINK-RELATIVE spelling must NOT exempt: the allowlist names real tracked paths,
# not the traversal's find -L output. Pins the documented spelling.
t="$(new_repo g5b)"; mkdir -p "$t/.claude" "$t/plugin/skills/x" "$t/.github"
printf 'path: %sdotfiles\n' "$homedir" > "$t/plugin/skills/x/SKILL.md"
ln -s "../plugin/skills/x" "$t/.claude/skills-x"
printf '.claude/skills-x/SKILL.md\n' > "$t/.github/.claude-governance-allow"
expect "G5b link-relative allow spelling  -> violation" 1 "hardcoded absolute home path" "$t"

# G6 — the staging/ vendored exemption holds through a link too: harvested third-party material
# reached via a directory symlink is exempt by PATH, same as when scanned directly.
t="$(new_repo g6)"; mkdir -p "$t/.claude" "$t/staging/harvest"
printf 'path: %sdotfiles\n' "$homedir" > "$t/staging/harvest/notes.md"
ln -s "../staging/harvest" "$t/.claude/vendor"
expect "G6 dir link -> staging/ material  -> clean" 0 "claude-config gate: clean" "$t"

# G6b — and the FILE-link spelling of the same thing (Devin, PR #1163): a single-file shortcut
# into staging/ must be as exempt as the directory-link spelling. Before the fix, the by-path
# skip applied only to the shortcut's own name, never to what it points at, so the exact same
# vendored file was exempt via `.claude/vendor -> ../staging/harvest` but a violation via
# `.claude/notes.md -> ../staging/harvest/notes.md`.
t="$(new_repo g6b)"; mkdir -p "$t/.claude" "$t/staging/harvest"
printf 'path: %sdotfiles\n' "$homedir" > "$t/staging/harvest/notes.md"
ln -s "../staging/harvest/notes.md" "$t/.claude/notes.md"
expect "G6b file link -> staging/ file    -> clean" 0 "claude-config gate: clean" "$t"

# G6c — the allowlist escape hatch holds for a FILE link too, matched on the target's
# repo-relative RESOLVED path (the real file's tracked spelling), same as G5's directory case.
t="$(new_repo g6c)"; mkdir -p "$t/.claude" "$t/plugin/skills/x" "$t/.github"
printf 'path: %sdotfiles\n' "$homedir" > "$t/plugin/skills/x/SKILL.md"
ln -s "../plugin/skills/x/SKILL.md" "$t/.claude/skill.md"
printf 'plugin/skills/x/SKILL.md\n' > "$t/.github/.claude-governance-allow"
expect "G6c file link -> allowlisted file -> clean" 0 "claude-config gate: clean" "$t"

# G6d — the negative control: a file link to NON-exempt dirty material must still be refused,
# or G6b/G6c would pass against a gate that skips every file-link target.
t="$(new_repo g6d)"; mkdir -p "$t/.claude" "$t/shared"
printf 'path: %sdotfiles\n' "$homedir" > "$t/shared/notes.md"
ln -s "../shared/notes.md" "$t/.claude/notes.md"
expect "G6d file link -> non-exempt dirty -> violation" 1 "hardcoded absolute home path" "$t"

# G7 — DANGLING LINKS BEHIND A DIRECTORY REDIRECT (Devin, PR #1163): under `find -L`, a broken
# symlink fails -type f, so the traversal never enumerated it and its home-path target string
# escaped both rules — the exact fail-open case D pins for top-level entries, hidden one
# directory link deep. The whole .claude dir is a link here, so the dangling link's own tracked
# path (config/claude/link) never matches the scope filter either.
t="$(new_repo g7)"; mkdir -p "$t/config/claude"
ln -s "${homedir}secret-config.json" "$t/config/claude/link"
ln -s "config/claude" "$t/.claude"
expect "G7 dir link -> dangling home link -> violation" 1 "symlink target is a hardcoded absolute home path" "$t"

# G7b — the flip side, mirroring case E through the redirect: a dangling link with a benign
# relative target is enumerated (counted as scanned) but is NOT a violation.
t="$(new_repo g7b)"; mkdir -p "$t/config/claude"
ln -s "shared/missing-but-benign" "$t/config/claude/link"
ln -s "config/claude" "$t/.claude"
expect "G7b dir link -> benign dangling   -> clean" 0 "claude-config gate: clean" "$t"

# G7c — EXEMPTIONS REACH DANGLING LINKS TOO (Devin, PR #1163): the top-level loop consults
# staging/ and the allowlist BEFORE its dangling-link branch, but walk_dir judged a broken link
# before either escape hatch, so vendored material fronted by `.claude -> staging/...` failed
# permanently on a broken home-path link with no way to approve it. Exempt by PATH, like G6.
t="$(new_repo g7c)"; mkdir -p "$t/staging/harvest"
ln -s "${homedir}secret-config.json" "$t/staging/harvest/link"
ln -s "staging/harvest" "$t/.claude"
expect "G7c staging redirect, dangling    -> clean" 0 "claude-config gate: clean" "$t"

# G7d — and the ALLOWLIST clears a dangling link too, matched on the documented repo-relative
# resolved spelling (parent's resolved path + basename, since the link itself cannot resolve).
t="$(new_repo g7d)"; mkdir -p "$t/config/claude" "$t/.github"
ln -s "${homedir}secret-config.json" "$t/config/claude/link"
ln -s "config/claude" "$t/.claude"
printf 'config/claude/link\n' > "$t/.github/.claude-governance-allow"
expect "G7d allowlisted dangling link     -> clean" 0 "claude-config gate: clean" "$t"

# G7e — THE ROOT-DIRECTORY EDGE (Devin, PR #1163): when the redirect resolves to the repo root
# itself (.claude -> .), the parent's resolved path IS $repo_root, so the slash-suffixed strip
# removed nothing and rel stayed ABSOLUTE — a spelling no allowlist entry could ever match,
# making a vetted dangling link at the root permanently un-exemptable.
t="$(new_repo g7e)"; mkdir -p "$t/.github"
ln -s "${homedir}secret-config.json" "$t/broken"
ln -s "." "$t/.claude"
printf 'broken\n' > "$t/.github/.claude-governance-allow"
expect "G7e root redirect, allowlisted    -> clean" 0 "claude-config gate: clean" "$t"

# G8 — PRUNE AT THE BOUNDARY (Devin, PR #1163): a NESTED link behind the directory redirect that
# resolves OUTSIDE the worktree used to have its whole outside tree enumerated by the full-walk
# `find -L` before the per-entry containment compare ran, and the violation line's link-relative
# tail named the outside file — a disclosure the message itself claimed to redact. The walk must
# refuse the escaping link itself and never walk (or name) anything beyond the boundary.
t="$(new_repo g8)"; mkdir -p "$t/config/claude" "$work/outside-g8"
printf 'model: opus\n' > "$work/outside-g8/private-notes-canary.txt"
ln -s "../../../outside-g8" "$t/config/claude/link"
ln -s "config/claude" "$t/.claude"
expect "G8 nested link escapes worktree   -> violation" 1 "resolves OUTSIDE the repository" "$t"
out="$(cd "$t" && git add -A && bash "$GATE" 2>&1)"
case "$out" in
  *private-notes-canary*) fail "G8b outside file names never printed — the traversal descended past the boundary" ;;
  *)                      pass "G8b outside file names never printed" ;;
esac

# G9 — LINK CYCLES TERMINATE (Devin, PR #1163): the level-by-level walk no longer leans on
# find -L's own loop detection, so a cycle behind the redirect (config/claude/self -> .) must be
# cut by the resolved-physical visited set — while dirty contents in the cycled tree are still
# found. A hang here IS the failure mode this pins against.
t="$(new_repo g9)"; mkdir -p "$t/config/claude"
printf 'path: %sdotfiles\n' "$homedir" > "$t/config/claude/settings.json"
ln -s "." "$t/config/claude/self"
ln -s "config/claude" "$t/.claude"
expect "G9 link cycle behind redirect     -> violation" 1 "hardcoded absolute home path" "$t"

# G4: CONTAINMENT (Devin, PR #1163): a link that RESOLVES outside the repo worktree is refused
# without reading the target; the gate must not scan (or print lines from) files beyond the repo.
t="$(new_repo g4)"; mkdir -p "$t/.claude"
printf 'model: opus\n' > "$work/outside-g4.txt"
ln -s "../../outside-g4.txt" "$t/.claude/link"
expect "G4 link resolves outside the repo  -> violation" 1 "resolves OUTSIDE the repository" "$t"

# Q: PORTABILITY (Devin, PR #1163): `readlink -f` is GNU-flavoured. Where readlink lacks `-f`
# (BSD/macOS, i.e. every LOCAL run of this script, per the fleet's own docs), the containment
# compare used to receive an empty resolution, read it as "outside the repository", and hard-fail
# a perfectly clean tree on its first resolvable link. Simulate that readlink with a PATH shim
# (rejects `-f`, passes everything else through) and assert the python3 realpath fallback keeps
# a clean in-repo dedupe clean, and still refuses a genuinely outside link, so "cannot resolve"
# and "resolved outside" stay distinct outcomes.
REAL_READLINK="$(command -v readlink)"
shim="$work/bsd-shim"; mkdir -p "$shim"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = "-f" ] && { echo "readlink: illegal option -- f" >&2; exit 1; }; done\nexec %s "$@"\n' "$REAL_READLINK" > "$shim/readlink"
chmod +x "$shim/readlink"

t="$(new_repo q)"; mkdir -p "$t/.claude" "$t/plugin/skills/x"
printf 'model: opus\n' > "$t/plugin/skills/x/SKILL.md"
ln -s "../plugin/skills/x" "$t/.claude/skills-x"
git -C "$t" add -A
out="$(cd "$t" && PATH="$shim:$PATH" bash "$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *"claude-config gate: clean"* ]]; then
  pass "Q  BSD readlink (no -f): clean dedupe -> clean"
else
  fail "Q  BSD readlink (no -f): clean dedupe -> clean (exit $rc)"
  printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
fi

t="$(new_repo q2)"; mkdir -p "$t/.claude"
printf 'model: opus\n' > "$work/outside-q2.txt"
ln -s "../../outside-q2.txt" "$t/.claude/link"
git -C "$t" add -A
out="$(cd "$t" && PATH="$shim:$PATH" bash "$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == *"resolves OUTSIDE the repository"* ]]; then
  pass "Q2 BSD readlink (no -f): outside link -> still refused"
else
  fail "Q2 BSD readlink (no -f): outside link -> still refused (exit $rc)"
  printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
fi

# H — no .claude at all: the documented no-op (most consumers are in this state).
t="$(new_repo h)"
expect "H  no tracked .claude/             -> clean no-op" 0 "0 tracked .claude/ file(s)" "$t"

# Z — THE ROOT GUARD MUST ACTUALLY FIRE (Devin, PR #1163): outside any git repo, the gate must
# refuse to run rather than scan the current directory as if it were a worktree. The old
# one-liner (`cd "$(git rev-parse ...)"`) could never trip: a failed rev-parse expands to "",
# `cd ""` succeeds without moving, and the guard branch was unreachable.
nong="$work/not-a-repo-z"; mkdir -p "$nong"
out="$(cd "$nong" && bash "$GATE" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && [[ "$out" == *"cannot resolve the repository root"* ]]; then
  pass "Z  not a git repo                 -> refused (exit 2)"
else
  fail "Z  not a git repo                 -> refused (exit $rc, want 2)"
  printf '       output: %s\n' "$(printf '%s' "$out" | head -3)"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "check-claude-config self-test: all cases pass"
  exit 0
fi
echo "check-claude-config self-test: $fails case(s) FAILED"
exit 1
