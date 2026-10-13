#!/usr/bin/env bash
# Buildkite step self-check-size: replaces GitHub Actions self-check/file-size, self-check/context-integrity.
# The gates are the verbatim `run:` bodies under .buildkite/gates/ (see lib/common.sh for the contract).
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_ensure_history
bk_gh_env
bk_gate 'file-size' self-check.file-size.01-file-size-gate-first-party-code-held-to.gate
bk_gate 'context-integrity' self-check.context-integrity.01-context-integrity-decompose-never-trim-c.gate
bk_gates_summary
