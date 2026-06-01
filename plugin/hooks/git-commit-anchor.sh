#!/usr/bin/env bash
# Hook: git-commit-anchor — stamps a recovery ref after every agent commit.
# Event: PostToolUse (matcher: Bash)
#
# WHY: on 2026-05-28 a concurrent session reset the branch and the in-progress commits became
# orphaned (recoverable only via reflog). This makes every agent commit reachable from a NAMED
# ref immediately, so a pointer move by another session can never lose it: the work is always
# one `git branch --list 'wip/anchor/*'` away, no reflog archaeology required.
#
# After a `git commit`, point  wip/anchor/<branch>  at HEAD (force-update the anchor only — never any
# other ref). Non-destructive and IDEMPOTENT: pointing the anchor at the current HEAD is harmless even
# if HEAD didn't move, so a dry-run is a safe no-op (we just suppress the message when nothing changed).

set +e
input=$(cat)
cmd=$(echo "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

# React only to an actual `git commit` SUBCOMMAND. Match `commit` followed by a space/EOL so plumbing
# like `commit-tree`/`commit-graph` is NOT matched; tolerate `git -c k=v commit` and ENV= prefixes.
echo "$cmd" | grep -qE '(^|[;&|][[:space:]]*)([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git([[:space:]]+-[cC][[:space:]]*[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || exit 0

# resolve the worktree we ran in (PostToolUse cwd is the tool's cwd)
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
head=$(git rev-parse --verify HEAD 2>/dev/null) || exit 0

branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
if [ -z "$branch" ]; then
  # detached HEAD — anchor by short sha so the work is still named/reachable
  branch="detached-$(git rev-parse --short HEAD 2>/dev/null)"
fi
# sanitize for a ref path (slashes in branch names are fine; spaces/odd chars are not)
safe=$(printf '%s' "$branch" | tr ' ' '-' | tr -cd 'A-Za-z0-9._/-')
# strip leading/trailing slashes; fall back to a sha-based name if sanitization emptied it
safe=$(printf '%s' "$safe" | sed -E 's#^/+##; s#/+$##')
[ -z "$safe" ] && safe="sha-$(git rev-parse --short HEAD 2>/dev/null)"
anchor="refs/heads/wip/anchor/${safe}"

# only ever move the anchor ref, to the new HEAD — touches nothing else. Report only when it actually
# advanced (so a dry-run, which leaves HEAD unchanged, stays silent).
prev=$(git rev-parse --verify --quiet "$anchor" 2>/dev/null)
git update-ref "$anchor" "$head" 2>/dev/null && [ "$prev" != "$head" ] &&
  echo "[git-commit-anchor] anchored ${head:0:8} → wip/anchor/${safe} (survives any branch reset)"

exit 0
