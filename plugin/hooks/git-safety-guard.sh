#!/usr/bin/env bash
# Hook: git-safety-guard — blocks history-/worktree-destroying git in agent sessions.
# Event: PreToolUse (matcher: Bash)
#
# WHY: a concurrent session ran `git reset` on a shared checkout and orphaned in-progress
# commits + wiped the working tree (wave-foundation incident 2026-05-28). circuit-breaker.sh
# only blocked force-push to main/master; this closes the rest of the destructive set.
#
# Blocks (deny): reset --hard/--keep · push --force / --force-with-lease (ANY branch, incl. combined
#   short flags like -uf) · clean -f* · branch -D · checkout/switch -f · update-ref -d
#   · reflog expire / gc --prune=now · rebase (except --abort/--continue/--skip)
#   · mass-staging sweeps (add -A / add --all / add .) · mass-deletion (rm -r / rm . / rm -r --cached)
#   · history rewrite (filter-repo / filter-branch).
# Allows: every non-destructive git (status/commit/fetch/pull/merge/log/diff/restore,
#   soft & mixed reset, branch -d, normal checkout/switch/push). `git add <named-path>` is fine —
#   only the blanket sweeps are blocked. `git rm <named-file>` is fine — only recursive/blanket rm.
#
# Each git invocation is evaluated INDEPENDENTLY: the command is split on shell separators
# (; | &, newlines) so a destructive op can't hide after a safe one in a chain
# (e.g. `git rebase --abort ; git rebase origin/master` — the 2nd segment is still caught).
# Flags between the subcommand and the destructive option are tolerated (e.g. `reset -q --hard`).
#
# Scope: guards AGENT Bash calls by design. A human who truly intends a destructive op runs it
# themselves in a terminal — the reason string tells the agent how to proceed safely.

set +e
input=$(cat)
cmd=$(echo "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
[ -z "$cmd" ] && exit 0

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Evaluate each shell segment on its own (here-string keeps the loop in THIS shell, so deny exits).
while IFS= read -r seg; do
  # strip leading whitespace + ENV=val assignments
  s=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//')
  # only inspect git invocations (tolerate `git -c k=v <sub>` global options)
  printf '%s' "$s" | grep -qE '^git([[:space:]]+-[cC][[:space:]]*[^[:space:]]+)*[[:space:]]+[a-z]' || continue

  # reset --hard / --keep (flags may sit between `reset` and the option)
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\breset\b' && printf '%s' "$s" | grep -qE -- '(--hard|--keep)\b' &&
    deny "BLOCKED: git reset --hard/--keep discards the working tree and can orphan commits (the 2026-05-28 incident). Use 'git stash' or a soft/mixed reset; if truly intended, run it yourself in a terminal."

  # force push — long flags OR any combined short-flag cluster containing f (-f, -uf, -fu)
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\bpush\b' &&
    printf '%s' "$s" | grep -qE -- '(--force(-with-lease)?\b|[[:space:]]-[A-Za-z]*f[A-Za-z]*\b)' &&
    deny "BLOCKED: force push can overwrite remote history other sessions depend on. Push normally or rebase+PR; run a force-push yourself if you really mean it."

  # git clean with -f anywhere in a short-flag cluster (-f, -fd, -xf, -dff)
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\bclean\b' &&
    printf '%s' "$s" | grep -qE -- '[[:space:]]-[A-Za-z]*f' &&
    deny "BLOCKED: git clean -f deletes untracked files irreversibly. Preview with 'git clean -n' first, then run it yourself if intended."

  # force branch delete
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\bbranch\b' && printf '%s' "$s" | grep -qE -- '[[:space:]]-D\b' &&
    deny "BLOCKED: git branch -D force-deletes a possibly-unmerged branch (orphans its commits). Use -d (merge-checked), or run -D yourself if intended."

  # forced checkout/switch
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\b(checkout|switch)\b' &&
    printf '%s' "$s" | grep -qE -- '([[:space:]]-[A-Za-z]*f[A-Za-z]*\b|--force|--discard-changes)' &&
    deny "BLOCKED: forced checkout/switch discards uncommitted changes. Commit or stash first; on a shared checkout prefer 'git worktree add' for a new branch."

  # direct ref deletion
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\bupdate-ref\b' && printf '%s' "$s" | grep -qE -- '[[:space:]]-d\b' &&
    deny "BLOCKED: git update-ref -d deletes a ref directly. Use 'git branch -d' / 'git tag -d' instead."

  # reflog/gc pruning — destroys the orphan-recovery net
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\b(reflog[[:space:]]+expire|gc)\b' &&
    printf '%s' "$s" | grep -qE -- '(--expire(-unreachable)?=(now|all)|--prune=now)' &&
    deny "BLOCKED: expiring the reflog / gc --prune=now destroys the recovery net for orphaned commits. Leave the reflog intact."

  # mass-staging sweep: `git add -A` / `add --all` / `add .` (also -u/--update blanket stage).
  # Stage named paths instead — a blanket sweep can pull in secrets (.env), large binaries, or
  # another session's in-progress edits on a shared checkout.
  if printf '%s' "$s" | grep -qE '^git[[:space:]].*\badd\b'; then
    printf '%s' "$s" | grep -qE -- '([[:space:]]-[A-Za-z]*[Au][A-Za-z]*\b|--all\b|--update\b)' &&
      deny "BLOCKED: 'git add -A/--all/-u/.' mass-stages everything — risks committing secrets (.env), large binaries, or another session's edits. Stage named paths: 'git add path/to/file'."
    printf '%s' "$s" | grep -qE -- '[[:space:]]\.([[:space:]]|$)' &&
      deny "BLOCKED: 'git add .' mass-stages the whole tree — risks committing secrets (.env), large binaries, or another session's edits. Stage named paths: 'git add path/to/file'."
  fi

  # mass-deletion: recursive `git rm -r` or a blanket `git rm .` (incl. --cached sweeps).
  # `git rm <named-file>` is allowed; only the recursive/whole-tree forms are blocked.
  if printf '%s' "$s" | grep -qE '^git[[:space:]].*\brm\b'; then
    printf '%s' "$s" | grep -qE -- '[[:space:]]-[A-Za-z]*r' &&
      deny "BLOCKED: 'git rm -r' recursively deletes tracked files (and from disk unless --cached). Remove named files explicitly, or run it yourself in a terminal if truly intended."
    printf '%s' "$s" | grep -qE -- '[[:space:]]\.([[:space:]]|$)' &&
      deny "BLOCKED: 'git rm .' deletes the whole tree. Remove named files explicitly, or run it yourself if intended."
  fi

  # history rewrite: filter-repo / filter-branch rewrite every commit and can unrecoverably
  # destroy work shared by other sessions/clones. Never let an agent do this.
  printf '%s' "$s" | grep -qE '^git[[:space:]].*\b(filter-repo|filter-branch)\b' &&
    deny "BLOCKED: git filter-repo/filter-branch rewrites the entire history and is unrecoverable on a shared repo. If you must scrub history, do it yourself in a dedicated clone."

  # rebase (per-segment, so a safe rebase elsewhere in a chain can't whitelist a destructive one).
  # Exception: dedicated worktrees (cwd is a linked worktree, not the primary checkout) — those
  # are precisely the safe place to rebase (the 2026-05-28 guidance the deny message points at).
  if printf '%s' "$s" | grep -qE '^git[[:space:]].*\brebase\b' &&
    ! printf '%s' "$s" | grep -qE -- '--(abort|continue|skip|edit-todo|show-current-patch|quit)\b'; then
    # Detect linked worktree: `git rev-parse --git-common-dir` differs from `--git-dir`.
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null || true)
    git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
    if [ -n "$common_dir" ] && [ -n "$git_dir" ] && [ "$common_dir" != "$git_dir" ]; then
      : # linked worktree — rebase is the intended workflow here
    else
      deny "BLOCKED: rebase rewrites history and, on a checkout shared by another session, stomps its working tree. Rebase inside a dedicated 'git worktree add' (this rule whitelists linked worktrees); --abort/--continue/--skip are allowed in the main checkout."
    fi
  fi
done <<<"$(printf '%s' "$cmd" | tr ';|&\n' '\n\n\n\n')"

exit 0
