#!/usr/bin/env bash
# Buildkite step node-suites: replaces GitHub Actions self-check/node-suites.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_assert_node_major
bk_ensure_history
bk_gh_env
bk_gate 'node-suites' self-check.node-suites.01-run-every-tracked-test-mjs-outside-packa.gate
bk_gates_summary
