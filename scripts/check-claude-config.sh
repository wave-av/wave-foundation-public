#!/usr/bin/env bash
# check-claude-config.sh — full-tree governance gate for project-level `.claude/` agent config.
#
# WHY THIS EXISTS (and why it is NOT redundant with the two existing org gates):
#   • .github/workflows/checks.yml "Secret scan" is whole-repo + fail-closed, but checks SECRETS only
#     (it has no hardcoded-path rule).
#   • .github/workflows/governance-enforce.yml (@wave-av/governance) checks secrets + hardcoded paths but
#     is DIFF-SCOPED (`enforce.mjs --changed <BASE>`): it blocks NEW violations and GRANDFATHERS legacy
#     debt — which is exactly why dozens of legacy `/Users/<name>/` absolute paths persist unfixed in some
#     repos' committed `.claude/` config.
# This gate closes that gap: it scans the ENTIRE tracked `.claude/**` tree (not the diff) for BOTH
#   (a) hardcoded absolute home paths (`/Users/<name>/`, `/home/<name>/`) — must be `$HOME` / `~`, and
#   (b) real-secret prefixes — agent config must never carry a materialized credential.
# It is scoped to `.claude/**` on purpose, so it forces the config we are STANDARDIZING to zero debt
# without failing the build on unrelated legacy elsewhere in the repo. (config-governed-like-prod LAW.)
#
# No-op in a repo with no tracked `.claude/` files. Read-only. Exit 0 = clean, 1 = violation found.
#
# SAFETY:
#   • NUL-delimited file iteration (`git ls-files -z`) — no word-splitting, no glob surprises.
#   • Secret matches are REDACTED in output (line numbers only, never the matched value) so the gate's
#     own CI logs can never leak a credential.
#   • Allowlist read is fail-OPEN (a missing allowlist = empty = the gate still runs on everything);
#     detection is fail-CLOSED (any hit => exit 1).
set -euo pipefail

ALLOW=".github/.claude-governance-allow"   # exact tracked paths to exempt (vetted); one per line, '#' = comment
# Allowlist spelling: the file's REPO-RELATIVE path. For a file reached THROUGH a directory
# symlink, that is the RESOLVED real path (e.g. plugin/skills/x/SKILL.md), never the
# link-relative spelling the traversal prints (.claude/skills-x/SKILL.md).

# Real-secret prefixes — mirrors the shapes in checks.yml so the two stay consistent. Anchored token
# shapes (length-bounded), not bare words, to keep false positives near zero.
SECRET_RE='(sk-[A-Za-z0-9]{20}|sk_(live|test)_[A-Za-z0-9]{20}|npm_[A-Za-z0-9]{30}|sbp_[a-f0-9]{40}|github_pat_[A-Za-z0-9_]{40}|ghp_[A-Za-z0-9]{30}|gho_[A-Za-z0-9]{30}|ghs_[A-Za-z0-9]{30}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIzaSy[A-Za-z0-9_-]{20}|xai-[A-Za-z0-9]{40}|xoxb-[A-Za-z0-9-]+|re_[A-Za-z0-9_]{20}|-----BEGIN [A-Z ]*PRIVATE KEY)'

# Hardcoded absolute home paths — portability LAW (no-hardcoded-paths): use $HOME / ~ / ${HOME}.
PATH_RE='(/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/)'

# fail-open: with no allowlist file, nothing is ever exempted and the gate still runs on everything.
allowed() { [ -f "$ALLOW" ] && grep -qxF "$1" "$ALLOW" 2>/dev/null; }

# ENUMERATE ONCE, FAIL CLOSED (#944). `done < <(git ls-files -z)` cannot propagate the lister's
# status, so a git failure left the loop with nothing to read, `scanned` at 0, and the gate printed
# "claude-config gate: clean (0 tracked .claude/ file(s) scanned; 0 secrets, 0 hardcoded paths)".
#
# Note the asymmetry the count makes visible. ZERO .claude/ FILES IS LEGITIMATE — the header above
# says so explicitly ("No-op in a repo with no tracked `.claude/` files"), and most of the 126
# consuming repos are in exactly that state. So the emptiness guard belongs on the WHOLE-TREE
# enumeration, not on the post-filter count: a repo with no tracked files at all is a broken
# invocation, whereas a repo with no `.claude/` files is the common case.
# The symlink handling below follows links, and a link may not read ANYTHING outside the repo
# worktree: a local run with a resolvable home-dir link would otherwise scan (and the path rule
# would print lines from) personal files. Physical path, so the containment compare is exact.
# TWO-STEP on purpose (Devin, PR #1163): the old one-liner `cd "$(git rev-parse ...)"` could never
# trip its own guard — when rev-parse fails the substitution is EMPTY, `cd ""` succeeds without
# moving, and repo_root silently became the CURRENT directory instead of aborting. Check the
# rev-parse result explicitly before cd-ing into it.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ] || ! repo_root="$(cd "$repo_root" && pwd -P)"; then
  echo "::error::claude-config: cannot resolve the repository root; refusing to run an unbounded scan." >&2
  exit 2
fi

list="$(mktemp)"
walk="$(mktemp -d)"          # per-level traversal listings + the visited set (see walk_dir below)
visited="$walk/visited"
chmod 0600 "$list"
chmod 0700 "$walk"
trap 'rm -f "$list"; rm -rf "$walk"' EXIT
if ! git ls-files -z >"$list"; then
  echo "::error::claude-config: git ls-files FAILED — refusing to report a clean gate. Nothing was scanned; treat this as blocked, not clean." >&2
  exit 2
fi
if [ ! -s "$list" ]; then
  echo "::error::claude-config: enumerated 0 tracked files. git succeeded, so this is a working-directory or repository problem, not an empty project — refusing to report a clean gate." >&2
  exit 2
fi

fail=0
scanned=0

# Content rules (a) secrets + (b) hardcoded home paths, applied to one file (grep follows a link).
# Shared by the direct scan and the directory-symlink traversal below so the two cannot drift.
scan_contents() { # $1=path
  local secret_lines path_hits
  # (a) secrets — REDACTED: report line numbers only, never the matched value.
  secret_lines=$(grep -nIE "$SECRET_RE" -- "$1" 2>/dev/null | cut -d: -f1 | paste -sd, - || true)
  if [ -n "$secret_lines" ]; then
    echo "::error::claude-config: $1 — secret-like credential at line(s) $secret_lines (value REDACTED). Agent config must never carry a materialized secret; reference Doppler/env NAMES and inject at launch (config-governed-like-prod LAW)."
    fail=1
  fi
  # (b) hardcoded home paths — echo the offending line for the fix, but FIRST mask any secret-shaped
  # token on that same line: a line can match BOTH a path and a secret, and the path print must not
  # leak what the secret check above redacted (caught by Cursor/WAVE BugBot review).
  path_hits=$(grep -nIE "$PATH_RE" -- "$1" 2>/dev/null | sed -E "s/$SECRET_RE/[REDACTED-SECRET]/g" || true)
  if [ -n "$path_hits" ]; then
    echo "::error::claude-config: $1 — hardcoded absolute home path (use \$HOME or ~):"
    printf '%s\n' "$path_hits" | sed 's/^/    /'
    fail=1
  fi
}

# Physical resolution for the containment compares below. `readlink -f` is GNU-flavoured: on a
# readlink without `-f` (BSD/macOS, where this script runs LOCALLY, per the fleet's own docs)
# the old inline substitution yielded an empty string, the containment case read that as
# "outside the repository", and every symlink on a perfectly clean tree hard-failed. Resolution
# and containment are different questions: try readlink -f, fall back to python3's realpath,
# and return NON-ZERO when neither works so the caller can report "unverifiable" (blocked)
# instead of the misleading "resolves OUTSIDE" (violation). Both outcomes still fail closed.
resolve_physical() { # $1=existing path -> physical absolute path on stdout; non-zero = unresolvable
  local r
  if r="$(readlink -f -- "$1" 2>/dev/null)" && [ -n "$r" ]; then printf '%s\n' "$r"; return 0; fi
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null
}

# DIRECTORY-SYMLINK TRAVERSAL, PRUNED AT THE BOUNDARY (Devin, PR #1163). The previous full-tree
# `find -L` followed NESTED symlinks before the per-entry containment compare ran, so an escaping
# link deep inside the target had its whole outside tree walked (unbounded) and the violation line
# carried the outside file's real name in its link-relative tail: a disclosure the message itself
# claimed to redact. walk_dir descends ONE LEVEL AT A TIME and containment-checks every entry
# BEFORE descending: an entry that resolves outside the worktree is refused as a single finding at
# the boundary link, and nothing beyond it is ever entered, enumerated, or named. Still fail-closed
# (#944): a directory that cannot be listed and an entry that cannot be resolved are violations,
# never clean. Prunes the same vendored dirs the old walk pruned (.git, node_modules, dist), and a
# visited set on resolved physical paths keeps link cycles finite (the old walk leaned on find -L's
# own loop detection, which only tripped AFTER descending).
walk_id=0
walk_dir() { # $1=directory reached through the tracked link (containment already verified)
             # $2=$1's resolved physical path (the caller already resolved it for containment)
  local dir="$1" rdir="$2" entries sub tgt masked rsub rel
  walk_id=$((walk_id + 1))
  entries="$walk/entries.$walk_id"
  # -H (not -L): follow $dir itself when it is a link, but list nested links AS links so find's
  # own loop detector never fires on a benign cycle; cycles are cut by the visited set instead.
  if ! find -H "$dir" -mindepth 1 -maxdepth 1 -print0 >"$entries" 2>/dev/null; then
    echo "::error::claude-config: $dir: cannot fully traverse the directory symlink target (unreadable entry). Refusing to report clean over an unscanned tree (config-governed-like-prod LAW)."
    fail=1
    return 0
  fi
  while IFS= read -r -d '' sub; do
    case "$sub" in */.git|*/node_modules|*/dist) continue ;; esac
    # DANGLING LINKS reached through the redirect (Devin, PR #1163): their target STRING is
    # itself config. Apply the same two rules as the top-level dangling-link branch, then move
    # on (nothing more to read). A benign relative dangling target stays clean, matching case E.
    # EXEMPTIONS FIRST (Devin, PR #1163): the top-level loop consults staging/ and the allowlist
    # BEFORE its dangling-link branch, so this branch must too — otherwise a broken link inside
    # vendored/approved material fails the gate with no escape hatch. The link itself cannot be
    # resolved, so derive its repo-relative path from the PARENT's resolved path + basename.
    # Strip the root WITHOUT its trailing slash, then drop the leading one (Devin, PR #1163):
    # when the walked link resolves to the repo root itself (.claude -> .), rdir IS $repo_root,
    # the slash-suffixed pattern strips nothing, and rel stays ABSOLUTE — a spelling no
    # staging/ or allowlist entry could ever match, so the escape hatches silently vanish.
    if [ -L "$sub" ] && [ ! -e "$sub" ]; then
      rel="${rdir#"$repo_root"}/${sub##*/}"; rel="${rel#/}"
      case "$rel" in staging/*) continue ;; esac
      allowed "$rel" && continue
      scanned=$((scanned + 1))
      tgt=$(readlink -- "$sub" 2>/dev/null || true)
      if printf '%s\n' "$tgt" | grep -qE "$SECRET_RE"; then
        echo "::error::claude-config: $sub — symlink target contains a secret-like credential (value REDACTED). Agent config must never carry a materialized secret (config-governed-like-prod LAW)."
        fail=1
      fi
      if printf '%s\n' "$tgt" | grep -qE "$PATH_RE"; then
        masked=$(printf '%s\n' "$tgt" | sed -E "s/$SECRET_RE/[REDACTED-SECRET]/g")
        echo "::error::claude-config: $sub — symlink target is a hardcoded absolute home path (use \$HOME or ~): $masked"
        fail=1
      fi
      continue
    fi
    # CONTAINMENT BEFORE DESCENT: refuse an out-of-worktree resolution here, at the boundary, so
    # the outside tree is never walked and only the in-repo link path is printed. Unresolvable =
    # unverifiable = blocked, never clean.
    if ! rsub="$(resolve_physical "$sub")"; then
      echo "::error::claude-config: $sub: cannot resolve physically (readlink lacks -f and python3 is unavailable). The containment check is unverifiable; refusing to report clean over an unverified link (config-governed-like-prod LAW)."
      fail=1
      continue
    fi
    case "$rsub/" in
      "$repo_root/"*) ;;
      *)
        echo "::error::claude-config: $sub: reachable through a directory symlink but resolves OUTSIDE the repository (target REDACTED). Refusing to descend past the worktree boundary."
        fail=1
        continue
        ;;
    esac
    if [ -d "$sub" ]; then
      grep -qxF "$rsub" "$visited" 2>/dev/null && continue   # link cycle or diamond: already walked
      printf '%s\n' "$rsub" >>"$visited"
      walk_dir "$sub" "$rsub"
      continue
    fi
    [ -f "$sub" ] || continue
    # EXEMPTIONS apply here too (Devin, PR #1163): a file reached through a directory link
    # must honour the same escape hatches as a directly-scanned one (the staging/ vendored
    # exemption and the vetted allowlist) or an exempted path becomes un-exemptable the
    # moment a dedupe link fronts it. Match on the REPO-RELATIVE RESOLVED path (the real
    # file's tracked spelling, per the $ALLOW note above): the traversal prints link-relative
    # paths the allowlist could never name.
    rel="${rsub#"$repo_root"/}"
    case "$rel" in staging/*) continue ;; esac
    allowed "$rel" && continue
    scanned=$((scanned + 1))
    scan_contents "$sub"
  done <"$entries"
  return 0
}

while IFS= read -r -d '' f; do
  # Scope: project-level agent config. The slash-less alternatives matter: git tracks no
  # directories, so an entry whose path IS `.claude` (or `dir/.claude`) can only be a SYMLINK —
  # the whole agent-config dir replaced by a link (e.g. into a personal home dir). Requiring a
  # slash after `.claude` filtered exactly that entry out before the symlink branch could test
  # its target, and the gate printed clean over zero scanned files.
  case "$f" in .claude|.claude/*|*/.claude|*/.claude/*) ;; *) continue ;; esac
  case "$f" in staging/*) continue ;; esac                       # vendored/harvested external material — exempt by PATH (mirrors the file-size gate)
  allowed "$f" && continue                                       # vetted exception (auditable in $ALLOW)
  # SYMLINKS: a symlink's target string is itself config, and `-f` FOLLOWS links — so a dangling
  # symlink whose target sits under an absolute home dir satisfied neither branch and was skipped
  # entirely while the gate still printed "clean". Fail-open by omission. Apply both rules to the
  # target STRING, then also scan the resolved contents when the link resolves (below).
  if [ -L "$f" ]; then
    scanned=$((scanned + 1))
    tgt=$(readlink -- "$f" 2>/dev/null || true)
    if printf '%s\n' "$tgt" | grep -qE "$SECRET_RE"; then
      echo "::error::claude-config: $f — symlink target contains a secret-like credential (value REDACTED). Agent config must never carry a materialized secret (config-governed-like-prod LAW)."
      fail=1
    fi
    if printf '%s\n' "$tgt" | grep -qE "$PATH_RE"; then
      masked=$(printf '%s\n' "$tgt" | sed -E "s/$SECRET_RE/[REDACTED-SECRET]/g")
      echo "::error::claude-config: $f — symlink target is a hardcoded absolute home path (use \$HOME or ~): $masked"
      fail=1
    fi
    # CONTAINMENT: whatever a resolvable link points at must live inside the repo worktree.
    # Outside it, the gate must not read (let alone print lines from) the target; the finding
    # is the escape itself, reported with the target REDACTED.
    if [ -e "$f" ]; then
      if ! resolved="$(resolve_physical "$f")"; then
        echo "::error::claude-config: $f: cannot resolve the symlink physically (readlink lacks -f and python3 is unavailable). The containment check is unverifiable; refusing to report clean over an unverified link (config-governed-like-prod LAW)."
        fail=1
        continue
      fi
      case "$resolved/" in
        "$repo_root/"*) ;;
        *)
          echo "::error::claude-config: $f: symlink resolves OUTSIDE the repository (target REDACTED). Agent config must not reach through the worktree boundary (config-governed-like-prod LAW)."
          fail=1
          continue
          ;;
      esac
    fi
    # A link that RESOLVES TO A DIRECTORY relocates governed config to paths this loop's scope
    # filter never visits (e.g. an in-repo config/claude/), so skipping it printed clean over an
    # unscanned tree. Scan every file reachable through the link instead: a benign in-repo dedupe
    # (.claude/skills/x -> ../plugin/skills/x) stays legal as long as its contents pass the same
    # two rules. walk_dir (above) does the traversal one level at a time, containment-checking
    # every entry BEFORE descending, so a nested link pointing outside the worktree is refused at
    # the boundary and the outside tree is never walked or named. Seed the visited set with this
    # link's own resolution so a cycle back to it terminates. (`-d` follows links; $resolved is
    # set: -d implies -e, so the containment block above already resolved this link.)
    if [ -d "$f" ]; then
      printf '%s\n' "$resolved" >"$visited"
      walk_dir "$f" "$resolved"
      continue
    fi
    # A RESOLVABLE link still exposes its target's CONTENTS through agent config — even a target
    # outside `.claude/**` (which the loop filter would never visit) or an untracked file present
    # in the checkout. Fall through to the content scan below (`grep` follows the link), exactly
    # as the pre-symlink-branch code did. Only a DANGLING link has nothing more to scan.
    [ -f "$f" ] || continue
    # EXEMPTIONS apply to a FILE link's target too (Devin, PR #1163): `.claude/x.md ->
    # ../staging/harvest/x.md` must stay as exempt as the directory-link spelling of the same
    # vendored material, or a repo carrying one allowed harvested file fails the gate. Match on
    # the repo-relative RESOLVED path, exactly like the directory traversal above ($resolved is
    # set here: -f implies -e, so the containment block already resolved this link).
    rel="${resolved#"$repo_root"/}"
    case "$rel" in staging/*) continue ;; esac
    allowed "$rel" && continue
  elif [ -f "$f" ]; then
    scanned=$((scanned + 1))
  else
    continue   # not a regular file and not a symlink — nothing scannable
  fi

  scan_contents "$f"
done <"$list"

if [ "$fail" = 0 ]; then
  echo "claude-config gate: clean ($scanned tracked .claude/ file(s) scanned; 0 secrets, 0 hardcoded paths)"
fi
exit "$fail"
