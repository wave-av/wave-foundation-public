#!/usr/bin/env bash
# Buildkite step self-check-secret-scan: replaces GitHub Actions self-check/secret-scan.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_gh_env
# The self-test's case N extracts checks.yml's inline block with `python3` + `import yaml`. The GH ubuntu runner's
# system python has PyYAML; golden v4.1 bakes it into every mise python, the pre-v4.1 image does not. Without it case
# N fails as "extraction failed", which reads as a broken gate: name the image gap instead, and still run both gates.
if ! bk_require_py_module yaml PyYAML; then
  bk_gate_fail 'prerequisite: python3 module yaml (PyYAML) is missing from the image (secret-scan self-test case N)'
fi
bk_gate 'secret-scan self-test (proves the gate still detects)' self-check.secret-scan.01-secret-scan-self-test-proves-the-gate-st.gate
bk_gate 'secret-scan (self, allowlist-aware)' self-check.secret-scan.02-secret-scan-self-allowlist-aware.gate
bk_gates_summary
