#!/usr/bin/env bash
# Buildkite step self-check-python: replaces GitHub Actions self-check/{skill-validate, version-sync, claude-api-shape,
# gate-registry-drift}.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract). GH's
# `setup-python` becomes a job-local venv first on PATH, so the verbatim `pip install pyyaml` steps install into it
# (PyPI egress).
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_ensure_history
bk_gh_env
# shellcheck disable=SC2119 # no package arguments: the verbatim pip gates install into the venv
bk_py_venv
bk_gate 'skill-validate: pip install pyyaml' self-check.skill-validate.01-pip-install-pyyaml.gate
bk_gate 'skill-validate' self-check.skill-validate.02-validate-skill-frontmatter.gate
bk_gate 'version-sync' self-check.version-sync.01-check-version-consistency.gate
bk_gate 'claude-api-shape' self-check.claude-api-shape.01-claude-api-request-shape-gate-canonical.gate
bk_gate 'gate-registry-drift: pip install pyyaml' self-check.gate-registry-drift.01-pip-install-pyyaml.gate
bk_gate 'gate-registry-drift' self-check.gate-registry-drift.02-gate-registry-pre-commit-parity.gate
bk_gates_summary
