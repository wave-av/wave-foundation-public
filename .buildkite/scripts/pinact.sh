#!/usr/bin/env bash
# Buildkite step pinact: replaces GitHub Actions pinact / pinact (all three steps).
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
#
# GH's step 1 downloads pinact v4.0.0 and checks its sha256, then `install`s it into /usr/local/bin. The CI guest
# has no root, so the same download, URL and sha256 (pinact.yml's PINACT_VERSION / PINACT_SHA256) land in a
# job-local bin instead; that install is this script's code, not a verbatim gate. pinact is not in the CI image, so
# this needs github.com release egress.
#
# GH gives `pinact run --check --verify` the job's github.token "to resolve SHA<->tag via API without anon rate
# limits". This pipeline holds no GitHub token, so --verify calls the GitHub API anonymously (60 requests/hour per
# egress IP). A rate-limited run fails the gate (never a pass). Giving this step a read-only GitHub token is a
# secrets decision listed in the PR, not made here.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_gh_env

PINACT_VERSION=4.0.0
# sha256 of pinact_linux_amd64.tar.gz from the v4.0.0 release checksums.txt (same value as .github/workflows/pinact.yml)
PINACT_SHA256=cc220902615325b10bd3bc52ed3de27488f79adaec52adcd12bd2194c2d2c592

bk_install_pinact() {
  local d
  bk_require_tools curl sha256sum tar || return 1
  if [[ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]]; then
    bk_err "the pinned pinact release is linux_amd64 only (this guest is $(uname -s)/$(uname -m))"
    return 1
  fi
  bk_mktemp_dir d
  curl -fsSL --retry 2 -o "$d/pinact.tar.gz" \
    "https://github.com/suzuki-shunsuke/pinact/releases/download/v${PINACT_VERSION}/pinact_linux_amd64.tar.gz" || return 1
  printf '%s  %s\n' "$PINACT_SHA256" "$d/pinact.tar.gz" | sha256sum -c - || return 1
  mkdir -p "$d/bin"
  tar -xzf "$d/pinact.tar.gz" -C "$d/bin" pinact || return 1
  chmod 0755 "$d/bin/pinact"
  PATH="$d/bin:$PATH"
  export PATH
  pinact --version
}

bk_section "install pinact v${PINACT_VERSION} (pinned + checksum-verified, job-local)"
if bk_install_pinact; then bk_record_gate 'install pinact (pinned)' 0 blocking; else bk_record_gate 'install pinact (pinned)' 1 blocking; fi
bk_gate 'pinact run --check --verify' pinact.pinact.02-verify-actions-are-sha-pinned.gate
bk_gate 'claude-chassis SHA pin' pinact.pinact.03-enforce-chassis-sha-pin-pinact-exempt.gate
bk_gates_summary
