#!/usr/bin/env bash
# Buildkite step zizmor: replaces GitHub Actions zizmor / zizmor.
#
# GH pip-installs zizmor 1.25.2 (version-pinned, no hash). The CI image bakes a newer zizmor, and a scanner version
# moves findings, so this keeps 1.25.2, installed from the vendor's GitHub release tarball and checked against the
# sha256 GitHub records for that asset (no PyPI fetch, no unverified byte). Findings fail the step, as on GH;
# .github/zizmor.yml is auto-discovered, as on GH.
#
# Not a verbatim gate: GH's audit step chooses its token from the run's secrets (on this public repository it falls
# back to the repo-scoped github.token and runs the online audits too). This pipeline holds no GitHub token, so the
# audit runs --no-online-audits, and the summary lists the online tier (impostor-commit, known-vulnerable actions) as
# SKIPPED on every build: visible, never folded into a pass. Arming it needs a read-only GitHub token on this step,
# a secrets decision listed in the PR.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_gh_env

ZIZMOR_VERSION=1.25.2
# GitHub's recorded digest of zizmor-x86_64-unknown-linux-gnu.tar.gz in the v1.25.2 release (verified on download)
ZIZMOR_SHA256=aa1facd105f0d83fe5c55b1adcd9d7417de5d83aa27471f91dc0b66cf3803577

bk_install_zizmor() {
  local d
  bk_require_tools curl sha256sum tar || return 1
  if [[ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]]; then
    bk_err "the pinned zizmor release is x86_64-linux only (this guest is $(uname -s)/$(uname -m))"
    return 1
  fi
  bk_mktemp_dir d
  curl -fsSL --retry 2 -o "$d/zizmor.tar.gz" \
    "https://github.com/zizmorcore/zizmor/releases/download/v${ZIZMOR_VERSION}/zizmor-x86_64-unknown-linux-gnu.tar.gz" || return 1
  printf '%s  %s\n' "$ZIZMOR_SHA256" "$d/zizmor.tar.gz" | sha256sum -c - || return 1
  mkdir -p "$d/bin"
  tar -xzf "$d/zizmor.tar.gz" -C "$d/bin" zizmor || return 1
  chmod 0755 "$d/bin/zizmor"
  PATH="$d/bin:$PATH"
  export PATH
  zizmor --version
}

bk_section "install zizmor ${ZIZMOR_VERSION} (GitHub release, sha256-verified, job-local)"
if bk_install_zizmor; then
  bk_record_gate 'install zizmor (pinned)' 0 blocking
  rc=0
  bk_section 'zizmor --no-online-audits .github/workflows/'
  zizmor --no-online-audits .github/workflows/ || rc=$?
  bk_record_gate 'zizmor (offline audits)' "$rc" blocking
  bk_skip 'zizmor online audits (impostor-commit, known-vulnerable actions): no GitHub read token on this step; secrets decision'
else
  bk_record_gate 'install zizmor (pinned)' 1 blocking
fi
bk_gates_summary
