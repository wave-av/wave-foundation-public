#!/usr/bin/env bash
# Drill for the CHANGELOG monotonicity guard in scripts/release.sh.
#
# WHAT IT PINS. `git-cliff -o CHANGELOG.md` rewrites the whole file. The pre-existing guard only
# asserts the NEW version's section arrived; it cannot see that older sections vanished. Twice on
# main a release cut deleted released history and passed:
#   d4f707c7 v1.12.0  59 sections -> 19
#   9102dc5d v1.14.0  21 sections ->  1  (2275 lines)
#
# HOW. Each case builds a scratch repo with its own bare origin and puts a STUB `git-cliff` first on
# PATH — a shell script that writes a controllable CHANGELOG so the drill decides what "regeneration"
# produces. Nothing replaces a system binary; the stub lives in the case's own mktemp dir and dies
# with it. `gh` is stubbed too, so no case can reach GitHub.
#
# The real release.sh runs to completion only in the passing cases; the refusing cases die before
# `git add`, which is the whole point — the guard sits before the commit, where the fix is cheap.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${WAVE_RELEASE_SCRIPT:-$HERE/../../scripts/release.sh}"
[ -f "$SCRIPT" ] || { echo "cannot find release.sh at $SCRIPT" >&2; exit 2; }
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

pass=0; fail=0
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# A CHANGELOG carrying $1 as the newest section plus every version listed in $2.
changelog() { # $1=newest  $2...=older versions ('!' prefix = tag deleted; stripped from the heading)
  printf '# Changelog\n\nAll notable changes to wave-foundation. Consumed by tag/SHA pin.\n\n'
  for v in "$@"; do printf '## [%s] - 2026-07-30\n\n### Features\n\n- thing (abc1234)\n\n' "${v#!}"; done
}

# Build a scratch repo whose committed CHANGELOG holds $2..., and whose stub git-cliff will emit
# exactly the versions named in $1 (comma-separated). Echoes the repo path.
make_repo() { # $1=what-cliff-emits (csv)  $2...=what-is-already-committed
  local emits="$1"; shift
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/relcl.XXXXXX")"
  mkdir -p "$d/repo/plugin/.claude-plugin" "$d/repo/.claude-plugin" "$d/repo/scripts" "$d/bin"
  git init -q -b main "$d/repo"
  git -C "$d/repo" config user.email drill@wave.online
  git -C "$d/repo" config user.name drill

  printf '{"version":"1.0.0"}\n' >"$d/repo/plugin/.claude-plugin/plugin.json"
  printf '{"plugins":[{"version":"1.0.0"}]}\n' >"$d/repo/.claude-plugin/marketplace.json"
  printf 'x\n' >"$d/repo/cliff.toml"
  changelog "$@" >"$d/repo/CHANGELOG.md"
  cp "$SCRIPT" "$d/repo/scripts/release.sh"
  chmod +x "$d/repo/scripts/release.sh"

  git -C "$d/repo" add -A
  git -C "$d/repo" commit -qm 'feat: base'
  # Tag EVERY version the fixture's changelog claims. release.sh carries forward only sections whose
  # tag is gone (unreproducible by construction) and leaves tagged-but-missing ones missing so the
  # guard reports them. Without these tags every case here would be silently repaired instead of
  # refused — the drill would pass by never reaching the condition under test.
  # A leading '!' marks a version whose tag was DELETED — the real v1.2.0/v1.2.1/v1.3.0 case.
  for v in "$@"; do case "$v" in !*) :;; *) git -C "$d/repo" tag "v$v";; esac; done
  git -C "$d/repo" commit -q --allow-empty -m 'feat: since the tag'

  # STUB git-cliff: ignores its args and writes whatever this case asked for.
  {
    echo '#!/usr/bin/env bash'
    echo 'out=CHANGELOG.md'
    echo 'for i in "$@"; do [ "$prev" = "-o" ] && out="$i"; prev="$i"; done'
    printf 'cat >"$out" <<'"'"'EOF'"'"'\n'
    changelog ${emits//,/ }
    echo 'EOF'
  } >"$d/bin/git-cliff"
  chmod +x "$d/bin/git-cliff"

  # STUB gh: a passing case must not reach GitHub. `pr list` returns nothing (no duplicate release).
  printf '#!/usr/bin/env bash\necho "gh $*" >>"%s/gh.log"\nexit 0\n' "$d" >"$d/bin/gh"
  chmod +x "$d/bin/gh"

  git init -q --bare "$d/origin.git"
  git -C "$d/repo" remote add origin "$d/origin.git"
  git -C "$d/repo" push -q origin main --tags
  # Both streams, not just stderr: `--set-upstream-to` reports on STDOUT, and this function's stdout
  # IS its return value — a stray line here becomes part of the path the caller cds into.
  git -C "$d/repo" branch --set-upstream-to=origin/main main >/dev/null 2>&1
  printf '%s' "$d"
}

# check <label> <repo-dir> <expect-rc|any> <must-contain> [must-NOT-contain] [VAR=VAL...]
check() {
  local label="$1" d="$2" want_rc="$3" want="$4" nowant="${5:-}"; shift 5 2>/dev/null || shift 4
  local out rc
  out="$(cd "$d/repo" && PATH="$d/bin:$PATH" env "$@" bash scripts/release.sh v1.1.0 2>&1)"
  rc=$?   # straight off the command substitution — a pipeline here would report the wrong status
  local ok=1
  [ "$want_rc" = "any" ] || [ "$rc" = "$want_rc" ] || ok=0
  case "$out" in *"$want"*) :;; *) ok=0;; esac
  if [ -n "$nowant" ]; then case "$out" in *"$nowant"*) ok=0;; esac; fi
  if [ "$ok" = 1 ]; then
    pass=$((pass+1)); printf 'ok    %-54s rc=%s\n' "$label" "$rc"
  else
    fail=$((fail+1)); printf 'FAIL  %-54s rc=%s (want rc=%s)\n' "$label" "$rc" "$want_rc"
    printf '%s\n' "$out" | sed 's/^/        | /' | head -14
  fi
  rm -rf "$d"
}

echo "== release.sh: CHANGELOG monotonicity guard =="

# THE REGRESSION THIS EXISTS FOR: regeneration keeps only the new section. Pre-fix this committed.
check "truncation to the newest section is REFUSED" \
  "$(make_repo '1.1.0' 1.0.0 0.9.0 0.8.0)" 1 "lost 3 previously-released section(s)" "chore(release)"

check "refusal names the missing versions" \
  "$(make_repo '1.1.0' 1.0.0 0.9.0 0.8.0)" 1 "[0.8.0]" ""

# Partial loss is the harder case: the file still looks plausible, just shorter.
check "partial loss is REFUSED too" \
  "$(make_repo '1.1.0,1.0.0' 1.0.0 0.9.0 0.8.0)" 1 "lost 2 previously-released section(s)" ""

# A count alone cannot see this: 3 sections in, 3 out, but one was swapped for another.
check "same COUNT with a swapped section is still caught" \
  "$(make_repo '1.1.0,1.0.0,0.7.0' 1.0.0 0.9.0 0.8.0)" 1 "lost 2 previously-released section(s)" ""

# A deliberate rewrite must stay reachable without editing the script.
check "WAVE_ALLOW_CHANGELOG_TRUNCATION=1 permits it" \
  "$(make_repo '1.1.0' 1.0.0 0.9.0 0.8.0)" any "dropping 3 previously-released section(s) on purpose" "REFUSING" \
  WAVE_ALLOW_CHANGELOG_TRUNCATION=1

# THE CONTROL. A normal cut appends and keeps everything — it must sail all the way through to the
# release PR. Asserted on a POSITIVE marker, not merely on the absence of "REFUSING": a case that
# dies for an unrelated reason also lacks that word, so "no refusal" alone would pass on a script
# that never reached the guard at all. This case passes against the unfixed script too, and should —
# it is what proves the other five measure the guard rather than a broken harness.
check "a normal append reaches the release PR" \
  "$(make_repo '1.1.0,1.0.0,0.9.0,0.8.0' 1.0.0 0.9.0 0.8.0)" 0 "Release PR" "REFUSING"

# A section whose TAG WAS DELETED is unreproducible by any config — the real v1.2.0/v1.2.1/v1.3.0
# case. It must be carried forward rather than refused, or every future cut is blocked forever.
check "tagless section is CARRIED FORWARD, not refused" \
  "$(make_repo '1.1.0,1.0.0' 1.0.0 '!0.9.0')" 0 "carried forward 1 section(s)" "REFUSING"

# ...and the distinction has to hold in BOTH directions in one file: carry the tagless one forward
# AND still refuse for the tagged one. Repairing what it can must not mask what it cannot.
check "tagless carried forward while a TAGGED loss still refuses" \
  "$(make_repo '1.1.0' 1.0.0 '!0.9.0')" 1 "REFUSING" ""

echo
if [ "$fail" -eq 0 ]; then
  echo "release-changelog-guard self-test: ${pass} case(s) passed"
  exit 0
fi
echo "release-changelog-guard self-test: ${fail} case(s) FAILED (${pass} passed)" >&2
exit 1
