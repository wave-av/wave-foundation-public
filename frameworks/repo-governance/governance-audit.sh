#!/usr/bin/env bash
# governance-audit.sh — sweep every wave-av repo against the matrix and print a gap report.
#
#   ./governance-audit.sh [org]            # default org: wave-av
#
# Remote-only (no checkouts): uses the GitHub community-profile API for the standard health files, the
# contents API for AGENTS.md / CHANGELOG.md / CODEOWNERS / .coderabbit.yaml, and the branch-protection
# API for gates. Org wave-av/.github defaults satisfy community-health files org-wide, so a per-repo
# "miss" on those is a soft gap; LICENSE/SECURITY/secret-scan on PUBLIC repos are hard (P0).
#
# Output: one row per repo with a compact flag string, then a P0 summary. Pure gh + jq.
set -euo pipefail
ORG="${1:-wave-av}"

# y/n helper for a contents path
has() { gh api "repos/$1/contents/$2" --silent >/dev/null 2>&1 && echo 1 || echo 0; }

# Org defaults: community-health files in $ORG/.github apply to EVERY repo lacking its own copy, so they
# are satisfied org-wide. NOTE: the community-profile API reports an empty `security_policy` even when an
# org-default SECURITY.md applies — so we detect SECURITY from the org default repo, not per-repo.
echo "Org defaults ($ORG/.github):"
for f in SECURITY.md CODE_OF_CONDUCT.md CONTRIBUTING.md SUPPORT.md AGENTS.md profile/README.md .github/PULL_REQUEST_TEMPLATE.md pull_request_template.md; do
  [ "$(has "$ORG/.github" "$f")" = 1 ] && echo "  ✓ default $f"
done
SEC_DEFAULT="$(has "$ORG/.github" SECURITY.md)"   # 1 ⇒ every repo has a SECURITY policy via the org default
echo

printf "%-26s %-4s  RE CH AG SE CO CR LI  prot reqd-checks\n" "REPO" "VIS"
echo   "──────────────────────────────────────────────────────────────────────────────"
p0=()
while IFS=$'\t' read -r name vis archived; do
  [ "$archived" = "true" ] && continue
  [ "$name" = ".github" ] && continue
  R="$ORG/$name"
  prof="$(gh api "repos/$R/community/profile" 2>/dev/null || echo '{}')"
  f() { echo "$prof" | jq -r ".files.$1 // empty" | grep -q . && echo 1 || echo 0; }
  re=$(f readme); li=$(f license); se=$(f security_policy)
  ch=$(has "$R" CHANGELOG.md); ag=$(has "$R" AGENTS.md)
  co=$(has "$R" CODEOWNERS); [ "$co" = 0 ] && co=$(has "$R" .github/CODEOWNERS)
  cr=$(has "$R" .coderabbit.yaml)
  branch="$(gh api "repos/$R" --jq '.default_branch' 2>/dev/null || echo main)"
  if gh api "repos/$R/branches/$branch/protection" --silent >/dev/null 2>&1; then
    prot="Y"
    checks="$(gh api "repos/$R/branches/$branch/protection" --jq '[.required_status_checks.checks[]?.context]|join(",")' 2>/dev/null | cut -c1-40)"
  else prot="n"; checks="(none)"; fi
  b() { [ "$1" = 1 ] && echo " ✓" || echo " ·"; }
  printf "%-26s %-4s  %s %s %s %s %s %s %s  %-4s %s\n" \
    "$name" "${vis:0:4}" "$(b $re)" "$(b $ch)" "$(b $ag)" "$(b $se)" "$(b $co)" "$(b $cr)" "$(b $li)" "$prot" "$checks"
  # P0: public repos missing protection, or missing LICENSE with no org default. SECURITY is covered by
  # the org default ($SEC_DEFAULT) regardless of the per-repo API field, so it is NOT a per-repo P0.
  if [ "$vis" = "public" ]; then
    [ "$li" = 0 ] && p0+=("$name: no LICENSE (and org default LICENSE may not apply)")
    [ "$prot" = "n" ] && p0+=("$name: no branch protection")
    [ "$SEC_DEFAULT" != 1 ] && [ "$se" = 0 ] && p0+=("$name: no SECURITY (and no org default)")
  fi
done < <(gh repo list "$ORG" --limit 200 --json name,visibility,isArchived \
          --jq '.[] | [.name, (.visibility|ascii_downcase), (.isArchived|tostring)] | @tsv' | sort)

echo
echo "Legend: RE=readme CH=changelog AG=agents.md SE=security CO=codeowners CR=coderabbit LI=license"
echo
if [ "${#p0[@]}" -gt 0 ]; then
  echo "🚨 PUBLIC P0 GAPS (exposure risk):"
  printf '  - %s\n' "${p0[@]}"
else
  echo "✓ no public P0 gaps"
fi
