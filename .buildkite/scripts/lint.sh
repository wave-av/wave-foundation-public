#!/usr/bin/env bash
# Buildkite step lint (pr_only): replaces GitHub Actions lint / shellcheck and lint / ruff.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
#
# The shellcheck gate: GH uses the ubuntu-24.04 runner's preinstalled shellcheck; the CI image bakes the same Ubuntu 24.04
# package (0.9.0). ruff: GH's `setup-python` 3.x plus `pip install ruff` (unpinned) becomes a job-local venv first
# on PATH and the same verbatim, unpinned `pip install ruff` (PyPI egress), so both read the same ruff release.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_require_tools shellcheck
bk_gh_env
shellcheck --version | sed -n 2p
bk_gate 'shellcheck (-S warning)' lint.shellcheck.01-shellcheck-s-warning.gate
# shellcheck disable=SC2119 # no package arguments: the verbatim pip gates install into the venv
bk_py_venv
bk_gate 'ruff: pip install ruff' lint.ruff.01-install-ruff.gate
bk_gate 'ruff (E4,E7,E9,F,W)' lint.ruff.02-ruff-e4-e7-e9-f-w.gate
bk_gates_summary
