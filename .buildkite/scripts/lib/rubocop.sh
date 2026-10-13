#!/usr/bin/env bash
# rubocop for the ruby ratchet leg, pinned by sha256. SOURCED by .buildkite/scripts/ratchet.sh after lib/common.sh.
#
# GH ratchet.yml `ruby` runs `gem install --user-install --no-document rubocop` (unpinned, whatever RubyGems
# resolves that day). The golden image bakes Ruby 3.3.12 as the default `ruby` but not rubocop (wave-ci
# docs/toolchain.md: "rubocop not yet baked ... next step is a hash-locked gem manifest"). This is that manifest,
# per job: every .gem is downloaded from rubygems.org, checked against the sha256 below, and only then installed
# with `gem install --local --ignore-dependencies --user-install`, so nothing is resolved at run time and no
# unverified byte is installed. --user-install puts the bin dir where the verbatim gate looks
# (`$(ruby -e 'puts Gem.user_dir')/bin`), as on GH.
#
# Provenance of the pins: the CHECKSUMS section of rails/rails Gemfile.lock at commit
# 07ac43aaefa1451c3076c317034880561b3c8e23 (2026-09-25; Bundler records the sha256 RubyGems serves). rubocop 1.90.0
# and its full runtime closure at the versions that lockfile resolved. `json` is not listed: Ruby 3.3.12's default
# json gem satisfies rubocop's `json (>= 2.3)`. prism and racc build native extensions here (the image's
# build-essential). UNVERIFIED on the guest: rubygems.org egress and the two native builds.
set -euo pipefail
: "${BK_REPO_ROOT:?lib/rubocop.sh must be sourced after lib/common.sh}"

BK_RUBOCOP_GEMS=(
  "ast 2.4.3 954615157c1d6a382bc27d690d973195e79db7f55e9765ac7c481c60bdb4d383"
  "language_server-protocol 3.17.0.6 5ef2c0c138f8267e1bc631d3328347d354f96724b0af22f2c79516120443b7f0"
  "lint_roller 1.1.0 2c0c845b632a7d172cb849cc90c1bce937a28c5c8ccccb50dfd46a485003cc87"
  "parallel 2.1.0 b35258865c2e31134c5ecb708beaaf6772adf9d5efae28e93e99260877b09356"
  "parser 3.3.12.0 21a6d7f755d5a24dfbdc6e6b772e4e879a52e7631a88bc5a3a134606052c9828"
  "prism 1.9.0 7b530c6a9f92c24300014919c9dcbc055bf4cdf51ec30aed099b06cd6674ef85"
  "racc 1.8.1 4a7f6929691dbec8b5209a0b373bc2614882b55fc5d2e447a21aaa691303d62f"
  "rainbow 3.1.1 039491aa3a89f42efa1d6dec2fc4e62ede96eb6acd95e52f1ad581182b79bc6a"
  "regexp_parser 2.12.0 35a916a1d63190ab5c9009457136ae5f3c0c7512d60291d0d1378ba18ce08ebb"
  "rubocop 1.90.0 9eb4c065b5c5154e4ef554c547972f3905a9eb6b53e657e580b6796b54bf8242"
  "rubocop-ast 1.50.0 b9ca88300da0803ee222ad20cdb30494c0a784eed06fdc35d254b06d662788db"
  "ruby-progressbar 1.13.0 80fc9c47a9b640d6834e0dc7b3c94c9df37f08cb072b7761e4a71e22cff29b33"
  "unicode-display_width 3.2.0 0cdd96b5681a5949cdbc2c55e7b420facae74c4aaf9a9815eee1087cb1853c42"
  "unicode-emoji 4.2.0 519e69150f75652e40bf736106cfbc8f0f73aa3fb6a65afe62fefa7f80b0f80f"
)

# bk_install_rubocop: download, verify and install the pinned closure. Returns non-zero on any miss (the caller
# records it as a failed setup gate; the ratchet gate then fails closed on the missing rubocop, as on GH).
bk_install_rubocop() {
  bk_require_tools ruby gem curl sha256sum || return 1
  local d spec name ver sum f
  local -a files=()
  bk_mktemp_dir d
  printf 'ruby %s\n' "$(ruby -e 'print RUBY_VERSION')"
  for spec in "${BK_RUBOCOP_GEMS[@]}"; do
    read -r name ver sum <<<"$spec"
    f="${d}/${name}-${ver}.gem"
    curl -fsSL --retry 2 -o "$f" "https://rubygems.org/downloads/${name}-${ver}.gem" || { bk_err "download of ${name}-${ver}.gem failed"; return 1; }
    printf '%s  %s\n' "$sum" "$f" | sha256sum -c --quiet - || { bk_err "${name}-${ver}.gem does not match its pinned sha256"; return 1; }
    files+=("$f")
  done
  gem install --local --ignore-dependencies --user-install --no-document "${files[@]}" || { bk_err "gem install of the pinned closure failed"; return 1; }
  PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH" rubocop --version
}
