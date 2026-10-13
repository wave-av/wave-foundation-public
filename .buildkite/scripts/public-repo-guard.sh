#!/usr/bin/env bash
# Buildkite step public-repo-guard: replaces GitHub Actions public-repo-guard / guard (gitleaks + content policy).
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
#
# GH downloads gitleaks 8.30.1 and checks its sha256, then `sudo install`s it, and apt-installs ripgrep when
# missing. The CI guest has no root and installs nothing ad hoc; the CI image bakes gitleaks 8.30.1 and ripgrep
# 15.2.0, so those two install steps are replaced by a version check of the image's gitleaks (a different version
# would move findings, so it fails the step rather than scan with it).
#
# GUARD_PRIVATE_REPOS: GH injects it from an org-level Actions variable, and content-policy.sh only runs its
# private-repo-name rule when it is set. The list is not public, so it cannot be written into this public repo's
# pipeline settings, and this pipeline has no non-public channel for it yet. Unset, the script skips that one rule
# (its own documented behaviour) and this step records the skip in its summary on every build. Every other rule,
# and gitleaks, runs exactly as on GH.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_gh_env

GITLEAKS_VERSION=8.30.1
bk_section "gitleaks: the image's install must be ${GITLEAKS_VERSION} (GH pins the same version)"
if bk_require_tools gitleaks rg && [[ "$(gitleaks version 2>/dev/null)" == "$GITLEAKS_VERSION" || "$(gitleaks version 2>/dev/null)" == "v$GITLEAKS_VERSION" ]]; then
  bk_record_gate "gitleaks ${GITLEAKS_VERSION} and ripgrep present (image)" 0 blocking
  bk_gate 'gitleaks (secret scan, published tree)' public-repo-guard.guard.02-gitleaks-secret-scan-published-tree.gate
  unset GUARD_PRIVATE_REPOS
  bk_gate 'content policy (trade-secret / internal-leak gate)' public-repo-guard.guard.04-content-policy-wave-trade-secret-interna.gate
  bk_skip 'content policy private-repo-name rule: GUARD_PRIVATE_REPOS has no non-public channel on this pipeline yet (see README)'
else
  bk_err "gitleaks ${GITLEAKS_VERSION} or ripgrep is missing from the image"
  bk_record_gate "gitleaks ${GITLEAKS_VERSION} and ripgrep present (image)" 1 blocking
fi
bk_gates_summary
