#!/usr/bin/env bash
# Buildkite step self-check-node: replaces GitHub Actions self-check/status-context-conformance, product-registry-drift,
# capabilities-honesty.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_assert_node_major
bk_gh_env
bk_gate 'status-context-conformance' self-check.status-context-conformance.01-status-context-conformance-no-new-collis.gate
bk_gate 'product-registry-drift' self-check.product-registry-drift.01-manifest-chassis-wave-products-parity.gate
# GH: `npm install --no-save --no-audit --no-fund tsx@4` (registry.npmjs.org egress), then the two honesty gates.
bk_gate 'capabilities-honesty: install tsx@4' self-check.capabilities-honesty.01-install-tsx.gate
bk_gate 'capabilities-honesty self-test (fixtures)' self-check.capabilities-honesty.02-honesty-check-self-test-fixtures.gate
bk_gate 'capabilities-honesty on own capabilities.json' self-check.capabilities-honesty.03-honesty-check-on-own-capabilities-json.gate
bk_gates_summary
