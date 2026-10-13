#!/usr/bin/env bash
# Buildkite step ratchet: replaces GitHub Actions ratchet / shell, python, cpp, rust, go, ruby.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source-path=SCRIPTDIR source=lib/rubocop.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/rubocop.sh"
bk_require_buildkite
bk_require_tools uv cppcheck cargo go
bk_ensure_history
bk_gh_env
# GH ran `pip install --user shellcheck-py==...` before the ratchet; same here (needs PyPI egress).
bk_gate "install shellcheck-py (pinned)" ratchet.shell.01-install-shellcheck-py-pinned-to-match-lo.gate
export PATH="$HOME/.local/bin:$PATH"
bk_gate 'shell ratchet' ratchet.shell.02-shell-ratchet.gate
bk_gate 'python ratchet' ratchet.python.01-python-ratchet.gate
# GH apt-installs cppcheck on ubuntu-24.04 (2.13.0); the golden image bakes the same Ubuntu 24.04 package.
bk_gate 'cpp ratchet' ratchet.cpp.02-cpp-ratchet.gate
bk_gate 'rust ratchet' ratchet.rust.02-rust-ratchet.gate
bk_gate 'go ratchet' ratchet.go.01-go-ratchet.gate
# Ruby leg. GH's `gem install --user-install rubocop` (unpinned) becomes the sha256-pinned closure of
# lib/rubocop.sh on the image's Ruby 3.3.12. A failed install is a failed gate; the ratchet gate still runs and
# fails closed (exit 2, "rubocop not found"), as it would on GH. The repo has zero *.rb today, so the ratchet itself
# is the dormant no-op the GH job documents.
bk_section 'install rubocop (sha256-pinned gem closure)'
if bk_install_rubocop; then bk_record_gate 'install rubocop (pinned)' 0 blocking; else bk_record_gate 'install rubocop (pinned)' 1 blocking; fi
bk_gate 'ruby ratchet' ratchet.ruby.02-ruby-ratchet.gate
bk_gates_summary
