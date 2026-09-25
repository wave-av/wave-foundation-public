#!/usr/bin/env bash
# WAVE public-repo content policy — the trade-secret / internal-leak gate.
#
# gitleaks catches FORMATTED secrets (API keys, tokens, private keys). This script
# catches the WAVE-specific things gitleaks does NOT: live billing identifiers,
# infra account IDs, hardcoded developer paths, private-repo names, and committed
# dotenv files. It is intentionally conservative (low false-positive) so it can be
# a BLOCKING merge gate on public repos.
#
# Scope: scans the working tree (the state being merged). Run AFTER checkout.
# Exits non-zero on any BLOCK violation. Allowlist a specific line with an inline
# `# guard:allow <reason>` comment, or exclude paths via a .guardignore (one glob
# per line) at the repo root.
#
# Usage: scripts/public-repo-guard/content-policy.sh [root]   (default root = .)
set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" || { echo "::error::content-policy: cannot cd to $ROOT"; exit 2; }
command -v rg >/dev/null 2>&1 || { echo "::error::content-policy: ripgrep (rg) required"; exit 2; }

VIOLATIONS=0

# Path globs exempt from scanning (vcs, vendored, build output, lockfiles, the
# gate's own pattern strings). Extend per-repo via .guardignore.
IGNORE=(
  -g '!**/.git/**'
  -g '!**/node_modules/**'
  -g '!**/dist/**' -g '!**/build/**' -g '!**/.next/**' -g '!**/target/**' -g '!**/vendor/**'
  -g '!**/*.lock' -g '!**/pnpm-lock.yaml' -g '!**/package-lock.json' -g '!**/Cargo.lock' -g '!**/go.sum'
  -g '!**/scripts/public-repo-guard/**'
  -g '!**/.gitleaks.toml'
)
if [[ -f .guardignore ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    IGNORE+=( -g "!$line" )
  done < .guardignore
fi

# check <BLOCK|WARN> <name> <regex> <why>
# A non-empty regex is required; an accidental empty pattern would match every
# line, so we guard against it explicitly.
check() {
  local sev="$1" name="$2" re="$3" why="$4"
  [[ -z "$re" ]] && { echo "::error::content-policy: internal bug — empty regex for rule '$name'"; exit 2; }
  # --hidden + --no-ignore-vcs so the scan covers dotfiles/dotdirs (.github/**,
  # .npmrc, …) and committed-but-gitignored files — a public leak hides there too.
  # rg exit: 0=match, 1=no match, >=2=real error → FAIL CLOSED (never pass a gate
  # silently because the scanner errored).
  local raw rc
  raw="$(rg -nP --hidden --no-ignore-vcs "${IGNORE[@]}" -- "$re" . 2>/dev/null)"; rc=$?
  if (( rc >= 2 )); then
    echo "::error title=public-repo-guard ($name)::ripgrep failed (exit $rc) scanning rule '$name' — failing closed."; exit 2
  fi
  # Only the documented inline form `# guard:allow <reason>` suppresses a hit, and
  # the reason is mandatory (non-space after the marker) — a bare marker, or the
  # string appearing elsewhere on the line, must NOT bypass detection.
  local matches
  matches="$(printf '%s' "$raw" | grep -vE '#[[:space:]]*guard:allow[[:space:]]+[^[:space:]]' || true)"
  [[ -z "$matches" ]] && return 0
  local count; count="$(printf '%s\n' "$matches" | grep -c '' )"
  echo "::group::[$sev] $name — $why"
  # Print only file:line — NEVER the matched content. On a public repo the Actions
  # log is public, so echoing the detected value would re-leak the secret itself.
  printf '%s\n' "$matches" | sed -E 's/^([^:]+:[0-9]+):.*/\1: «match redacted — open this location to view»/'
  echo "::endgroup::"
  if [[ "$sev" == "BLOCK" ]]; then
    echo "::error title=public-repo-guard ($name)::$why — $count occurrence(s). Remove it, or annotate the line with '# guard:allow <reason>' if it is a verified-safe example."
    VIOLATIONS=$((VIOLATIONS+1))
  else
    echo "::warning title=public-repo-guard ($name)::$why — $count occurrence(s) (non-blocking; review)."
  fi
}

# --- Financial / billing identifiers -----------------------------------------
check BLOCK stripe-account   'acct_[A-Za-z0-9]{16,}'                              'Live Stripe account ID — financial infra, never publish'
check BLOCK stripe-live-key  '(sk|rk)_live_[A-Za-z0-9]{16,}'                      'Live Stripe secret/restricted key'
check WARN  stripe-object    '(cus|sub|price|prod)_[A-Za-z0-9]{14,}'             'Stripe object ID — verify it is an EXAMPLE, not a real account object'

# --- Infrastructure identifiers ----------------------------------------------
# shellcheck disable=SC2016  # $CLOUDFLARE_ACCOUNT_ID is literal guidance text, not meant to expand
check BLOCK cf-account-id    'account_id\s*[:=]\s*["'"'"']?[0-9a-f]{32}'          'Hardcoded Cloudflare account_id — source it from $CLOUDFLARE_ACCOUNT_ID'

# --- Internal network identifiers --------------------------------------------
# Tailscale CGNAT range (100.64.0.0/10) — internal fleet IPs must never appear in
# a public tree. Narrow on purpose: never trips 127.0.0.1, 0.0.0.0, public IPs, or
# RFC1918 documentation addresses. Pattern is byte-for-byte lockstep with
# foundation's sync-public.sh / verify-public-mirror.sh INTERNAL_IP_PAT, so the
# pre-publish mirror gate and this public-repo gate agree on the same leak class.
check BLOCK internal-ip      '100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}'  'Internal Tailscale-CGNAT IP (100.64.0.0/10) — internal fleet address, never publish'

# --- Developer / private-repo leakage ----------------------------------------
# shellcheck disable=SC2016  # $HOME is literal guidance text, not meant to expand
check BLOCK abs-user-path    '/(Users|home)/(?!runner/)[a-z][a-z0-9._-]+/'        'Hardcoded developer absolute path — use $HOME or a CLI argument'

# --- Unresolvable cross-repo references (three shapes) -----------------------
# A public repo must not reference something a public consumer cannot resolve. A
# reference into a wave-av repo that is NOT this repo's own `-public` sibling gets
# ZERO successful runs, forever (GitHub Actions refuses a public repo consuming a
# private repo's reusable workflow — the run fails before any job is created; see
# frameworks/ambiguity-gate/DECISIONS.md ADR-002 / ADR-008). Three shapes, three
# rules, all org-scoped rather than a blanket private-repo-name scan, so each fires
# on the reference SHAPE regardless of which repo is named and without depending on
# GUARD_PRIVATE_REPOS being set.
#
# All three anchor on the org-scoped PATH, never on a surrounding YAML key. That is
# a correction, not a preference: this rule was originally `uses:`-anchored, and a
# prose comment quoting the identical unresolvable path was invisible to it. On the
# tree where that was found, the `uses:`-anchored rule reported 0 matches while a
# line carrying the shape sat in .github/workflows/pr-agent.yml — "clean by the
# rule" and "clean of the shape" are different claims, and only the second is worth
# making. A commented reference is still the payload: it teaches a reader to write
# the broken thing, and one copy-paste into a workflow ships the failure.
#
# SHAPE 1 — a reusable workflow (`.github/workflows/<name>.yml`). The `uses:` case
# is a strict subset of the path match, so quoted forms (`uses: "wave-av/…"`,
# `uses: 'wave-av/…'`) that the old optional-quote class existed to cover are now
# covered by construction rather than by an extra alternation.
check BLOCK unresolvable-uses 'wave-av/(?:(?!-public/)[\w.-])+/\.github/workflows/' \
  'Reusable-workflow path in a non -public wave-av repo — unresolvable for a public consumer, 0 successful runs ever'

# SHAPE 2 — a COMPOSITE ACTION (`.github/actions/<name>`) owned by a wave-av repo
# that is not this repo's own `-public` sibling. A public consumer resolves it
# exactly as badly as the reusable workflow above — the job fails before the step
# runs — so it is the same leak class with a different path suffix. This one was
# never `uses:`-anchored: every occurrence found when it was written sat in a PROSE
# COMMENT (a zizmor ignore-rationale) with no `uses:` token on the line, which is
# what prompted re-anchoring shape 1 to match.
#
# The two resolvable forms stay clean: a same-repo local `uses: ./.github/actions/x`
# carries no owner/repo prefix and cannot match, and this repo's own `-public`
# sibling is exempted by the same `(?!-public/)` lookahead used above.
check BLOCK unresolvable-action 'wave-av/(?:(?!-public/)[\w.-])+/\.github/actions/' \
  'Composite-action path in a non -public wave-av repo — unresolvable for a public consumer, 0 successful runs ever'

# SHAPE 3, and the most dangerous of the three: a RUNTIME fetch of a file out of a
# wave-av repo that is not this repo's own `-public` sibling, via
# raw.githubusercontent.com. Unlike shapes 1 and 2 this one does NOT fail in
# CI — the tree is valid, every gate reports green, and the 404 lands later, in a
# consumer's environment, at the moment the script or hook actually runs. Anything
# that swallows the failure (`2>/dev/null`, `|| true`, an unchecked response) turns
# it from a crash into a silent wrong answer, which is strictly worse.
#
# Not anchored on a file extension or on any surrounding syntax: the URL is the
# payload whether it sits in a shell variable, a TypeScript string literal, a JSON
# hook config or a docs code fence. `(?!-public/)` exempts this repo's own published
# raw content, and the pattern is URL-host-specific so an ordinary github.com
# issue/PR hyperlink into a non -public repo — which resolves fine for anyone with
# access and fetches nothing at run time — is untouched.
check BLOCK unresolvable-raw-fetch 'raw\.githubusercontent\.com/wave-av/(?:(?!-public/)[\w.-])+/' \
  'raw.githubusercontent.com fetch from a non -public wave-av repo — 404s at run time in a public consumer environment, never in CI'

# Private WAVE repo/product names that must never appear in a public tree. The
# names are NOT hardcoded here (this file is itself public) — they are supplied
# at run time via GUARD_PRIVATE_REPOS (CI injects it from an org-level Actions
# variable), comma- or space-separated. Unset locally → this check is skipped.
if [[ -n "${GUARD_PRIVATE_REPOS:-}" ]]; then
  IFS=', ' read -r -a _PRIV <<< "$GUARD_PRIVATE_REPOS"
  for _name in "${_PRIV[@]}"; do
    [[ -z "$_name" ]] && continue
    # Regex-escape the name so metacharacters in a repo name (., -, etc.) match
    # literally rather than changing the pattern's meaning.
    _esc="$(printf '%s' "$_name" | sed -E 's/[][(){}.^$*+?|\\]/\\&/g')"
    check BLOCK private-repo "\\b${_esc}\\b" 'Reference to a private WAVE repo/product (configured via GUARD_PRIVATE_REPOS) — keep out of public'
  done
fi

# --- Credential formats gitleaks may miss in-context -------------------------
check BLOCK anthropic-key    'sk-ant-(api|admin)[0-9]{2}-[A-Za-z0-9_-]{20,}'      'Real Anthropic API/admin key'
check BLOCK github-pat       'github_pat_[A-Za-z0-9_]{30,}'                       'GitHub fine-grained PAT'
check BLOCK supabase-pat     'sbp_[a-f0-9]{40}'                                   'Supabase personal access token'
check BLOCK aws-akid         'AKIA[0-9A-Z]{16}'                                   'AWS access key ID'
check BLOCK private-key      '-----BEGIN [A-Z ]*PRIVATE KEY-----'                 'Embedded private key material'

# --- Committed dotenv (real env, not templates) ------------------------------
# List candidate files with the SAME ignore filtering as check() so .guardignore
# and the standard excludes apply to this BLOCK rule too. Match `.env` plus any
# `.env.*` variant (development, test, …), then drop template forms. Include-globs
# come first; the IGNORE excludes come last (last match wins, so a .env under e.g.
# node_modules stays excluded). --hidden because these are dotfiles; --no-ignore-vcs
# so a committed-but-gitignored .env is still caught; fail CLOSED on rg error.
_envraw="$(rg --files --hidden --no-ignore-vcs -g '.env' -g '.env.*' "${IGNORE[@]}" 2>/dev/null)"; _envrc=$?
if (( _envrc >= 2 )); then
  echo "::error title=public-repo-guard (committed-dotenv)::ripgrep failed (exit $_envrc) — failing closed."; exit 2
fi
ENVHITS="$(printf '%s\n' "$_envraw" | grep -vE '\.(example|sample|template|dist)$' | grep -vE '^$' || true)"
if [[ -n "$ENVHITS" ]]; then
  echo "::group::[BLOCK] committed-dotenv — real .env files must not be committed"
  printf '%s\n' "$ENVHITS"
  echo "::endgroup::"
  echo "::error title=public-repo-guard (committed-dotenv)::Committed .env file(s). Commit only .env.example/.sample/.template."
  VIOLATIONS=$((VIOLATIONS+1))
fi

if (( VIOLATIONS > 0 )); then
  echo "::error::public-repo-guard: $VIOLATIONS blocking content-policy violation(s) — see annotations above."
  exit 1
fi
echo "public-repo-guard: content policy OK"
