#!/usr/bin/env bash
# Buildkite step gate-self-tests: replaces GitHub Actions self-check/gate-self-tests.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract). GH's
# `setup-python` becomes a job-local venv first on PATH; the verbatim `pip install pyyaml` installs into it.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_gh_env
# shellcheck disable=SC2119 # no package arguments: the verbatim pip gates install into the venv
bk_py_venv
bk_gate 'gate-self-tests: pip install pyyaml' self-check.gate-self-tests.01-pip-install-pyyaml.gate
bk_gate 'gate-self-tests' self-check.gate-self-tests.02-run-every-frameworks-gates-test-sh.gate
bk_gates_summary
