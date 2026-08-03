#!/usr/bin/env bash
# release.sh — one-command release cutter for wave-foundation.
#
# Usage:
#   scripts/release.sh vX.Y.Z
#
# Bumps the plugin + marketplace version, regenerates CHANGELOG.md (promoting the [unreleased]
# section to the new version), commits on a release/vX.Y.Z branch, pushes, and opens an
# auto-merge PR. Branch protection is respected — nothing is pushed to main directly.
#
# After the PR merges, publish the release by tagging main (the script prints the exact
# commands). The tag triggers release.yml (release notes + CycloneDX SBOM asset).
set -euo pipefail

VERSION="${1:-}"
PLUGIN_JSON="plugin/.claude-plugin/plugin.json"
MARKET_JSON=".claude-plugin/marketplace.json"
# Derived from the checkout, not hardcoded, because this script now publishes to the
# public mirror. A copy running there would open its PR LOCALLY (gh pr create targets
# the local remote) and then POST labels to a hardcoded wave-av/wave-foundation using
# the LOCAL PR number -- labelling an unrelated PR in a different repo. Acting on
# whatever repo you are actually standing in is the only safe default for a script
# that exists in more than one of them. Falls back to the canonical slug.
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
REPO="${REPO:-wave-av/wave-foundation}"

die() {
  echo "error: $*" >&2
  exit 1
}

# --- validate argument ---
[ -n "$VERSION" ] || die "usage: scripts/release.sh vX.Y.Z"
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be semver with a leading v (vX.Y.Z), got: $VERSION"
NUM="${VERSION#v}"

# --- preconditions ---
command -v git-cliff >/dev/null 2>&1 || die "git-cliff not installed (brew install git-cliff)"
command -v gh >/dev/null 2>&1 || die "gh CLI not installed"
[ -f "$PLUGIN_JSON" ] || die "run from the repo root ($PLUGIN_JSON not found)"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || die "cut releases from main (currently on '$branch')"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree is not clean — commit or stash first"
fi
# --tags is load-bearing, not tidiness. Tags are what git-cliff uses as version boundaries and what
# `git describe` below reads to find the previous release. A cut run against a checkout that cannot
# see its own tags produces a CHANGELOG with a single unbounded section — which is what the v1.14.0
# cut committed (2275 lines deleted). --force so a moved tag (v1) updates instead of being skipped.
git fetch --quiet --tags --force origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "local main is not in sync with origin/main — pull first"

# Match only full vX.Y.Z tags, not the moving major tag (v1), so "latest" is the real last release.
latest="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || echo v0.0.0)"
[ "$VERSION" != "$latest" ] || die "version $VERSION is already the latest tag"
greatest="$(printf '%s\n%s\n' "$latest" "$VERSION" | sort -V | tail -1)"
[ "$greatest" = "$VERSION" ] || die "version $VERSION must be greater than the latest tag $latest"

# --- duplicate-release guard: don't race another session/agent cutting a release ---
# With multiple agents on this repo, two of them can independently start cutting a release. Either the
# SAME version (a collision) or two DIFFERENT versions in flight at once (the second silently obsoletes
# the first). Refuse both: a release/* branch already on origin, or any open `chore(release):` PR.
relbranch="release/$VERSION"
if git ls-remote --exit-code --heads origin "refs/heads/$relbranch" >/dev/null 2>&1; then
  die "release branch $relbranch already exists on origin — another session may be cutting $VERSION. Check open PRs (gh pr list --search 'chore(release): in:title')."
fi
open_rel="$(gh pr list --repo "$REPO" --state open --search 'chore(release): in:title' --json number,title,headRefName -q '.[] | "  #\(.number) \(.title) [\(.headRefName)]"' 2>/dev/null || true)"
if [ -n "$open_rel" ]; then
  die "a release PR is already open — land or close it before cutting $VERSION:
$open_rel"
fi

echo "Cutting $VERSION (previous: $latest)"

# --- release branch ---
git switch -c "$relbranch"

# --- bump versions (regex replace preserves each file's formatting) ---
# plugin.json carries ONE top-level version; marketplace.json carries one version PER plugin entry
# (wave-foundation, wave-mcp, …) which the version-sync gate requires in lockstep. So bump EVERY match
# in marketplace.json — not just the first. (count=1 previously left wave-mcp stale and red-gated the
# v1.8.6 cut.) The regex only matches semver-shaped "version" fields, and both manifests contain no
# other such field, so replace-all is safe here.
bump_version() { # $1=path  $2=max replacements (0 = all)
  python3 -c '
import re, sys
path, num, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
text = open(path, encoding="utf-8").read()
new = re.sub(r"(\"version\":\s*\")[0-9]+\.[0-9]+\.[0-9]+(\")",
             lambda m: m.group(1) + num + m.group(2), text, count=count)
if new == text:
    sys.exit(f"no version field bumped in {path}")
open(path, "w", encoding="utf-8").write(new)
' "$1" "$NUM" "$2"
}
bump_version "$PLUGIN_JSON" 1 # single top-level plugin version
bump_version "$MARKET_JSON" 0 # every plugins[].version (0 = replace all)

# --- regenerate the changelog, promoting [unreleased] to this version ---
# Snapshot the version headings BEFORE regenerating. `-o` overwrites the whole file, so once
# git-cliff has run the previous contents exist only in git — read them from HEAD, never from disk.
prev_versions="$(mktemp)"
new_versions="$(mktemp)"
prev_file="$(mktemp)"
tags_file="$(mktemp)"
trap 'rm -f "$prev_versions" "$new_versions" "$prev_file" "$tags_file"' EXIT
git show HEAD:CHANGELOG.md >"$prev_file" 2>/dev/null || true
grep -oE '^## \[[^]]+\]' "$prev_file" | sort -u >"$prev_versions" || true

git-cliff --config cliff.toml --tag "$VERSION" -o CHANGELOG.md

# --- carry forward ONLY the sections git-cliff genuinely cannot regenerate ---
# Some released sections have no tag left to derive them from: v1.2.0, v1.2.1 and v1.3.0 were
# deleted from the repo, so no tag_pattern brings them back. Those must be carried forward or every
# cut loses them, and a guard that fires on the normal path is one people learn to bypass.
#
# But carrying forward EVERYTHING missing would be worse than the bug. The v1.14.0 failure was a
# checkout that could not see its tags; blanket repair would paper over exactly that, restore all 65
# sections, and hand back a file that looks perfect while the release it describes was computed from
# a broken view of history.
#
# So the rule is drawn on evidence, not on volume: a section whose TAG STILL EXISTS must be
# regenerable, and if it is not, the environment is wrong and the guard below should say so. Only
# tagless sections — unreproducible by construction — are carried forward.
git tag -l >"$tags_file"
python3 - "$prev_file" CHANGELOG.md "$tags_file" <<'PY'
import re, sys
SEC = re.compile(r'^## \[([^\]]+)\]', re.M)

def split(text):
    ms = list(SEC.finditer(text))
    head = text[:ms[0].start()] if ms else text
    out = []
    for i, m in enumerate(ms):
        end = ms[i + 1].start() if i + 1 < len(ms) else len(text)
        out.append((m.group(1), text[m.start():end].rstrip() + '\n'))
    return head, out

old = open(sys.argv[1], encoding='utf-8').read()
new = open(sys.argv[2], encoding='utf-8').read()
if not old.strip():
    sys.exit(0)

head, new_secs = split(new)
_, old_secs = split(old)
have = {n for n, _ in new_secs}
tags = set(open(sys.argv[3], encoding='utf-8').read().split())

def regenerable(name):
    """A section is git-cliff's to produce iff a tag it can traverse still exists."""
    return name in tags or f'v{name}' in tags

# Leave regenerable-but-missing sections MISSING on purpose, so the guard below reports them.
missing = [(n, b) for n, b in old_secs if n not in have and not regenerable(n)]
if not missing:
    sys.exit(0)

# Re-insert after the section that preceded it in the OLD file, so ordering survives; if that
# neighbour is itself gone, fall back to the end rather than guessing a position.
order = [n for n, _ in new_secs]
bodies = dict(new_secs)
old_names = [n for n, _ in old_secs]
for name, body in missing:
    i = old_names.index(name)
    prev = old_names[i - 1] if i else None
    bodies[name] = body
    order.insert(order.index(prev) + 1 if prev in order else len(order), name)

out = head + '\n'.join(bodies[n] for n in order)
open(sys.argv[2], 'w', encoding='utf-8').write(re.sub(r'\n{3,}', '\n\n', out).rstrip() + '\n')
sys.stderr.write(f"carried forward {len(missing)} section(s) git-cliff could not regenerate: "
                 f"{', '.join(n for n, _ in missing[:5])}\n")
PY
# Collapse blank-line runs git-cliff emits across version joins so the file is markdownlint-clean.
python3 -c '
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(re.sub(r"\n{3,}", "\n\n", s).rstrip() + "\n")
' CHANGELOG.md

# --- fail early if git-cliff emitted no section for this version ---
# git-cliff can absorb a version's commits into a PRIOR tag's section: when a concurrent release
# is cut and merged back into this branch, those commits resolve to the older tag in git-cliff's
# traversal, leaving [$NUM] empty and unemitted. The downstream release.yml guard catches this only
# AFTER the tag is pushed (a failed release + a tag that must be force-moved to recover). Catch it
# here, before the commit, where the fix is a cheap hand-edit. (task #66)
if ! grep -qE "^## \[${NUM}\]" CHANGELOG.md; then
  die "git-cliff produced no '## [${NUM}]' section in CHANGELOG.md.
This usually means a concurrent release was merged back into this branch, so git-cliff grouped
${VERSION}'s commits under an earlier tag. Add the '## [${NUM}]' section by hand (list the feat/fix
commits in ${latest}..HEAD), re-run, or fix cliff.toml tag scoping. See task #66."
fi

# --- fail if regenerating DROPPED any previously-released section ---
# The check above proves the NEW section arrived. It says nothing about whether the old ones
# survived, and `git-cliff -o` rewrites the entire file from whatever history it can see. When it
# can see less than the full tag range — a shallow clone, unfetched tags, a cliff.toml scoping
# change — it emits a correct-looking file containing only the newest section, and the guard above
# passes because the thing it looks for is right there at the top.
#
# That is not hypothetical. It has happened twice on main and neither cut noticed:
#   d4f707c7 chore(release): v1.12.0   59 version sections -> 19   (40 dropped)
#   9102dc5d chore(release): v1.14.0   21 version sections ->  1   (2275 lines deleted)
#
# Compare the NAME SET, not the count: a count is unchanged when one section is swapped for
# another, which is the case a release cut is most likely to produce.
grep -oE '^## \[[^]]+\]' CHANGELOG.md | sort -u >"$new_versions"
missing="$(comm -13 "$new_versions" "$prev_versions" || true)"
if [ -n "$missing" ]; then
  n_missing="$(printf '%s\n' "$missing" | grep -c '^')"
  preview="$(printf '%s\n' "$missing" | head -5 | tr '\n' ' ')"
  if [ "${WAVE_ALLOW_CHANGELOG_TRUNCATION:-0}" = "1" ]; then
    echo "::warning::WAVE_ALLOW_CHANGELOG_TRUNCATION=1 — dropping ${n_missing} previously-released section(s) on purpose: ${preview}"
  else
    die "REFUSING to commit a CHANGELOG that lost ${n_missing} previously-released section(s).
  Missing: ${preview}
  git-cliff rewrote CHANGELOG.md from a narrower view of history than the file already recorded.
  Almost always this means the checkout cannot see the older tags: run
    git fetch --tags --force origin
  and re-run. A shallow clone (fetch-depth) will do the same thing.
  The changelog is consumed by tag/SHA pin, so a truncated one is lost release history, not cosmetics.
  Deliberate rewrite: WAVE_ALLOW_CHANGELOG_TRUNCATION=1 (say so out loud in the PR)."
  fi
fi

# --- commit, push, open auto-merge PR ---
git add "$PLUGIN_JSON" "$MARKET_JSON" CHANGELOG.md
git commit -m "chore(release): $VERSION"
git push -u origin "$relbranch"

gh pr create --title "chore(release): $VERSION" --body "Automated release cut by scripts/release.sh.

- bump plugin + marketplace version to $NUM
- regenerate CHANGELOG.md (\`## [$NUM]\`)

After this auto-merges, tag main to publish the release (notes + SBOM)."
prnum="$(gh pr view "$relbranch" --json number -q .number)"
gh api -X POST "repos/$REPO/issues/$prnum/labels" -f "labels[]=automerge" >/dev/null

major="v${NUM%%.*}" # e.g. v1 — the moving major tag consumers pin (@v1) for non-breaking updates

cat <<EOF

Release PR #$prnum opened for $VERSION.
After it auto-merges, publish the release:

  git checkout main && git pull --ff-only
  git tag $VERSION && git push origin $VERSION
  scripts/advance-major-tag.sh $major          # safely advance the moving major tag (gate self-test + newest-release check)

The vX.Y.Z tag triggers release.yml (release notes + CycloneDX SBOM). The moving $major tag is what
consumers reference (uses: .../checks.yml@$major) so they get non-breaking v${NUM%%.*}.x updates.
advance-major-tag.sh refuses to point $major at a commit that fails the gate self-tests or isn't the
newest $major.* release — so a stale/buggy gate can never be activated fleet-wide by a bare force-push.
EOF
