#!/usr/bin/env bash
# repo-governance-check.sh — verify ONE repo against the WAVE governance matrix.
#
#   ./repo-governance-check.sh [--dir <path>] [--visibility public|private] [--remote <owner/repo>] [--kind service|sdk|lib]
#
# Two independent layers:
#   • FILES  — required files present in --dir (a checkout). Org wave-av/.github defaults cover the
#              common ones, so missing community-health files are reported as INFO (default may apply)
#              unless --strict (then WARN). LICENSE/SECURITY for public are always ERROR (P0).
#   • GATES  — when --remote <owner/repo> is given, query GitHub for branch protection + required status
#              checks and verify the matrix's gate set is enforced.
#
# Exit non-zero if any ERROR. Pure bash + gh + jq; no network unless --remote.
set -euo pipefail

DIR="."; VIS=""; REMOTE=""; KIND="lib"; STRICT=0
while [ $# -gt 0 ]; do case "$1" in
  --dir) DIR="$2"; shift 2;;
  --visibility) VIS="$2"; shift 2;;
  --remote) REMOTE="$2"; shift 2;;
  --kind) KIND="$2"; shift 2;;
  --strict) STRICT=1; shift;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

errors=0; warns=0
err()  { echo "  ✗ [ERROR] $1"; errors=$((errors+1)); }
warn() { echo "  ⚠ [WARN]  $1"; warns=$((warns+1)); }
ok()   { echo "  ✓ $1"; }
info() { echo "  · $1"; }

# Auto-detect visibility from the remote if not given.
if [ -z "$VIS" ] && [ -n "$REMOTE" ]; then
  VIS="$(gh repo view "$REMOTE" --json visibility --jq '.visibility' 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
fi
VIS="${VIS:-private}"
echo "── governance: ${REMOTE:-$DIR}  (visibility=$VIS, kind=$KIND) ──"

# Present if the file exists at root OR under .github/ (GitHub resolves both).
have() { [ -e "$DIR/$1" ] || [ -e "$DIR/.github/$1" ]; }

# ── FILES ──────────────────────────────────────────────────────────────────────
# common to all repos; community-health ones can be satisfied by the org .github defaults.
for f in README.md CHANGELOG.md AGENTS.md; do
  if have "$f"; then ok "file $f"; else err "missing $f"; fi
done
for f in SECURITY.md CODEOWNERS .coderabbit.yaml; do
  if have "$f"; then ok "file $f"
  elif [ "$f" = "SECURITY.md" ] && [ "$VIS" = "public" ]; then err "missing $f (public P0)"
  elif [ "$STRICT" = 1 ]; then warn "missing $f (org .github default may apply)"
  else info "no own $f (org .github default may apply)"; fi
done
if [ "$VIS" = "public" ]; then
  have LICENSE && ok "file LICENSE" || err "missing LICENSE (public P0)"
  for f in CODE_OF_CONDUCT.md CONTRIBUTING.md SUPPORT.md; do
    have "$f" && ok "file $f" || info "no own $f (org .github default may apply)"
  done
fi
if [ "$KIND" = "service" ] || [ "$KIND" = "sdk" ]; then
  have llms.txt && ok "file llms.txt" || warn "missing llms.txt (agent discovery for $KIND)"
fi

# ── GATES (remote) ───────────────────────────────────────────────────────────────
if [ -n "$REMOTE" ]; then
  branch="$(gh repo view "$REMOTE" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo main)"
  prot="$(gh api "repos/$REMOTE/branches/$branch/protection" 2>/dev/null || echo '')"
  if [ -z "$prot" ]; then
    err "no branch protection on $branch"
  else
    echo "$prot" | jq -e '.required_pull_request_reviews' >/dev/null 2>&1 && ok "gate PR-required" || err "gate: PRs not required"
    echo "$prot" | jq -e '.enforce_admins.enabled==true' >/dev/null 2>&1 && ok "gate enforce_admins" || warn "gate: enforce_admins off"
    checks="$(echo "$prot" | jq -r '.required_status_checks.checks[]?.context // .required_status_checks.contexts[]?' 2>/dev/null | tr '\n' ' ')"
    want="secret"; echo "$checks" | grep -qiE 'secret' && ok "gate secret-scan required" || err "gate: secret-scan not required ($want)"
    echo "$checks" | grep -qiE 'coderabbit|bot.review' && ok "gate review-bot required" || warn "gate: review bot not required"
    if [ "$VIS" = "public" ]; then
      echo "$checks" | grep -qiE 'scorecard' && ok "gate scorecard (public)" || warn "gate: OpenSSF Scorecard not required (public)"
      echo "$checks" | grep -qiE 'socket|semgrep|sca|dependency' && ok "gate SCA (public)" || warn "gate: SCA not required (public)"
    fi
    [ -n "$checks" ] && info "required checks: $checks" || warn "no required status checks configured"
  fi
fi

echo "── result: $errors error(s), $warns warning(s) → $([ "$errors" -eq 0 ] && echo PASS || echo FAIL) ──"
[ "$errors" -eq 0 ]
