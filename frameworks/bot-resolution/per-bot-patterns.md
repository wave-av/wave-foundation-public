# Per-bot resolution patterns

The README covers the loop. This file covers each bot's quirks — the things
that trip an agent up if they're not documented.

## CodeRabbit

**Identifier**: `coderabbitai` (login) — but our scripts match by App type, not login.

**Severity scale**:

- 🔴 Critical — security / correctness; blocking
- 🟠 Major — likely defect; blocking
- 🟡 Minor — nit / style; not blocking
- ⚡ Quick win — drive-by suggestion; not blocking

**Quirk 1 — stale line numbers post-rebase.** After you fix and force-push,
CodeRabbit re-reviews but its OLD threads sometimes still appear "open" because
the line is unchanged but its line numbers shifted. **Fix**: the Bot Review Gate
workflow auto-resolves these (thread.outdated check). If it's slow,
`scripts/resolve-bot-threads.sh <PR>` does the same job on-demand.

**Quirk 2 — anti-pattern self-hits.** A linter docfile that *quotes* the forbidden
pattern (e.g. `check-model-strings.sh` quoting `claude-sonnet-4-6-20251114` as
the anti-pattern it bans) triggers the linter on itself. **Fix**: append
`claude-api-lint: ignore` to the quoted line so the lint skips it.

**Quirk 3 — script-executed analysis.** CodeRabbit sometimes runs a verification
script as part of its review (look for "🏁 Script executed:" sections). If it
contradicts the PR's claim ("this CLI flag doesn't exist"), it's almost always
right. Don't argue — fix.

**Commands**:

- `@coderabbitai resolve` — close the thread the comment lives on
- `@coderabbitai pause` — stop reviews on this PR
- `@coderabbitai review` — force re-review at current SHA
- `@coderabbitai ignore` — mark this finding as won't-fix (still visible, doesn't block)

## Cursor BugBot

**Identifier**: `cursor` (App).

**Severity**: opaque — Cursor treats all findings as "potential issues" without
explicit severity. Treat each one as 🟠 Major by default; downgrade with
justification.

**Quirk 1 — "Fix all" link.** Top-level review comment has a `[Cursor: open in Cursor]`
link that opens the IDE with pending edits. The foundation accepts this flow but
require **per-finding commits** (one commit per fix) for reviewability.

**Quirk 2 — style-only suggestions.** Cursor often suggests rewrites that don't
match the foundation's style. Reject those with `[Cursor: ignore]` and a short
reason. Don't accept style changes that conflict with `frameworks/conventions/`.

**Commands**: none — the `[Cursor: …]` brackets in *your* PR description are the
only control surface.

## Cubic

**Identifier**: `cubic` (App).

**Severity**: 🔴 Blocking / 🟡 Suggestion. Blocking findings block the gate.

**Quirk 1 — no resolve command.** Cubic uses GitHub's native thread resolution.
Click "Resolve conversation" on each thread, or use `scripts/resolve-bot-threads.sh`.

**Quirk 2 — finds duplicates of other bots.** Cubic, CodeRabbit, and Cursor
often flag the same issue. Resolve one, the others stay open until the bot
re-reviews. The aggregator (`pr-review-extract.sh`) de-dupes in the sticky
comment but the individual threads stay separate.

## Sentry Seer

**Identifier**: `sentry-io` (App) + `sentry-toolkit` (sometimes).

**Severity**: not on the PR — Sentry posts the finding link, the severity lives
in Sentry itself. Treat as 🟠 Major by default.

**Quirk 1 — PR comments rot.** When the PR closes, Sentry's PR comments are
abandoned. The durable artifact is the Linear issue (synced via
`frameworks/observability`). **Always** check the linked Linear issue before
resolving; close the Linear issue when fixed, not just the PR thread.

**Quirk 2 — Seer suggestions are advisory.** Even when Seer proposes a code
change, evaluate it as a hypothesis — sometimes it's wrong. Don't auto-accept.

**Commands**: none on the PR; commands live in Linear.

## Socket Security

**Identifier**: `socket-security` (App).

**Severity**: advisory (capability alerts on new deps — install scripts, network,
shell). Never blocking by default.

**Quirk 1 — new-dep noise.** Every Dependabot bump triggers a Socket review on
the transitive deps. Most are noise. Configure `socket.yml` per the
`frameworks/security-scanners` standard to filter by capability set.

**Quirk 2 — install-script red flag.** A capability tagged
`install-scripts` is rarely benign; treat as 🟠 Major and investigate the
publisher before merging.

**Commands**: none — configure via `socket.yml`.

## Dependabot

**Identifier**: `dependabot[bot]` (bot).

**Severity**: based on advisory severity (high/critical advisories label the PR).

**Auto-merge eligibility**:

- Lockfile-only changes (`package-lock.json`, `go.sum`, `Cargo.lock`) → auto-merge
- Patch + minor bumps within `^X.Y.Z` constraint → auto-merge
- Major version bumps → human review required
- Any high/critical advisory → security-team review required

**Commands** (post as comment on the PR):

- `@dependabot rebase`
- `@dependabot merge`
- `@dependabot squash and merge`
- `@dependabot ignore this version`
- `@dependabot ignore this major version`
- `@dependabot close`

## Renovate

**Identifier**: `renovate[bot]` (bot).

**Severity**: same as Dependabot, plus a "Merge Confidence" score (0-100%).

**Auto-merge eligibility**: same rules as Dependabot, plus a Merge Confidence
floor of 80% for any auto-merge.

**Commands**:

- `@renovatebot rebase`
- `@renovatebot recreate`
- `@renovatebot ignore`
- `@renovatebot retry`
- `pin`, `unpin`, `prefer pinned` — adjust pinning policy

## Greptile (where used)

**Identifier**: `greptile-apps` (App).

Long-form architectural reviews; advisory.

**Quirk**: posts huge multi-paragraph reviews. Skim, extract concrete actions,
then `@greptile resolve <thread>` after.

## When all else fails

If a bot is producing too much noise and you can't tune it:

1. **Don't disable the App at the org level** — it loses signal for other repos.
2. **Don't add to the script's bot exclusion list** — that's a global decision.
3. **Do** open a Linear issue tagged `bot-tuning` with the false-positive examples,
   and adjust the bot's config (`.coderabbit.yml`, `socket.yml`, etc.) to
   suppress that specific class of finding repo-wide.

This is the foundation's principled escape — narrow tuning beats blanket
suppression.
