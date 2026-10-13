#!/usr/bin/env bash
# Buildkite step pr-metadata (DEFERRED, pr_only, see wave-ci.deferred.json): replaces semantic-pr / validate-title,
# which reads PR facts Buildkite does not give a job (title and body).
#
# Where the facts would come from: a read-only PR metadata file, /run/wave-ci/pr.json, that the CI host fetches with
# its own read-only credential and places in the guest; no GitHub token enters the guest. Every string in it is
# untrusted: it is read with jq into a variable and handed to the verbatim gates through their environment
# (PR_TITLE / PR_BODY, the names GH's `env:` used), never eval'd and never pasted into a command line.
#
# Why parked: the file reaches only jobs on the per-job queue, and the pinned renderer routes a step there only when
# it declares a secret; this step holds none. Until a secret-free PR-metadata step can be routed there, rendering it
# would fail every PR build at "no /run/wave-ci/pr.json". GH's semantic-pr stays the gate meanwhile.
#
# GH's first step is amannn/action-semantic-pull-request (an action, no `run:`). The workflow's own comment says its
# parity step, frameworks/hooks/validate-conventional-title.sh, is the rule CI enforces, so that verbatim gate stands
# for both. The whole job is continue-on-error on GH, so all three gates are advisory here.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
bk_require_buildkite
bk_require_tools jq
bk_gh_env

PR_JSON=/run/wave-ci/pr.json
if [[ "$GITHUB_EVENT_NAME" != "pull_request" ]]; then
  bk_skip 'semantic-pr: not a pull request build (GH runs it on pull_request only)'
  bk_gates_summary
  exit 0
fi
if [[ ! -f "$PR_JSON" ]] || ! jq -e '.schema == "wave.ci-pr-metadata/v1"' "$PR_JSON" >/dev/null 2>&1; then
  bk_err "no valid ${PR_JSON} on this PR build: the step is not opted in to host-fetched PR metadata"
  bk_gate_fail 'read PR metadata'
  bk_gates_summary
fi
if [[ "$(jq -r '.head.sha' "$PR_JSON")" != "$(git rev-parse HEAD)" ]]; then
  bk_gate_fail 'read PR metadata (pr.json head.sha is not this build commit)'
  bk_gates_summary
fi
PR_TITLE="$(jq -r '.title // ""' "$PR_JSON")"
PR_BODY="$(jq -r '.body // ""' "$PR_JSON")"
export PR_TITLE PR_BODY

bk_gate 'semantic-pr: conventional title (shared validator)' semantic-pr.validate-title.01-validate-title-with-the-shared-script-pa.gate advisory
bk_gate 'semantic-pr: breaking-change indicator' semantic-pr.validate-title.02-check-for-breaking-change-indicator.gate advisory
bk_gate 'semantic-pr: ambiguity gate' semantic-pr.validate-title.03-ambiguity-gate-advisory.gate advisory
bk_gates_summary
