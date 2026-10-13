#!/usr/bin/env bash
# Shared helpers for .buildkite/scripts/*.sh. SOURCED by every step script, never run directly.
#
# Contract every step script inherits from here:
#   - `set -euo pipefail`, and never `set -x` (xtrace would print expanded values into the build log).
#   - No step of this pipeline holds a credential. Nothing here receives, stores or forwards one: every
#     credential-shaped name an agent environment hook might still export is unset before any gate runs.
#   - BUILDKITE_BRANCH / BUILDKITE_MESSAGE / PR titles are untrusted data: never eval'd, never interpolated
#     into a command string. A BUILDKITE_* value used as an argument is validated first and passed as one argv.
#   - Temp dirs are job-local and removed on exit.
#   - Gates are the VERBATIM `run:` bodies of the GitHub Actions steps they replace (.buildkite/gates/), each
#     run as `bash -e <file>` (the GH default shell) with the GH context they read emulated by bk_gh_env below.
#     A gate failing never stops the other gates in the step: every gate runs, then bk_gates_summary prints one
#     verdict line per gate and the step fails if any blocking gate failed.
set -euo pipefail

BK_REPO_SLUG="wave-av/wave-foundation-public"
BK_REQUIRED_NODE_MAJOR="24"
BK_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export BK_REPO_ROOT
cd "$BK_REPO_ROOT"

# No credentials in this pipeline (see .buildkite/README.md "Credentials"). Drop anything credential-shaped.
unset NODE_AUTH_TOKEN NPM_TOKEN GITHUB_TOKEN GH_TOKEN DOPPLER_TOKEN CLOUDFLARE_API_TOKEN CLOUDFLARE_DEPLOY_TOKEN

_bk_cleanup_paths=()
_bk_failed=()
_bk_passed=()
_bk_advisory=()
_bk_skipped=()

bk_cleanup_on_exit() {
  local p
  for p in "${_bk_cleanup_paths[@]+"${_bk_cleanup_paths[@]}"}"; do
    rm -rf -- "$p"
  done
}
trap bk_cleanup_on_exit EXIT

bk_section() { printf -- '--- %s\n' "$*"; }
bk_err() { printf 'error: %s\n' "$*" >&2; }
bk_warn() { printf 'warning: %s\n' "$*" >&2; }

# Fork pull requests are never built on this pipeline. The fence is the pipeline setting
# build_pull_request_forks: false (a fork PR never reaches an agent, so none of the code below ever runs
# for one). This check is a TRIPWIRE, not a boundary: this file is read from the PR's own checkout, so a
# hostile fork could delete it. It exists so that a misconfigured pipeline (fork builds switched on by hand)
# turns a benign fork PR's build red and loud on the first step, instead of quietly running it.
BK_SAME_REPO_RE='^(https://|git://|ssh://git@|git@)github\.com[:/]wave-av/wave-foundation-public(\.git)?$'
if [[ "${BUILDKITE_PULL_REQUEST:-false}" != "false" && ! "${BUILDKITE_PULL_REQUEST_REPO:-}" =~ $BK_SAME_REPO_RE ]]; then
  bk_err "this is a pull request from another repository (a fork). Fork PRs are never built on this pipeline; build_pull_request_forks must be false. Refusing."
  exit 1
fi

# bk_mktemp_dir <var>: job-local temp dir, removed on exit, path stored in <var> (not printed, so the
# cleanup registration survives; a $(...) subshell would lose it).
bk_mktemp_dir() {
  local __dir
  __dir="$(mktemp -d "${TMPDIR:-/tmp}/bk.XXXXXX")"
  _bk_cleanup_paths+=("$__dir")
  printf -v "$1" '%s' "$__dir"
}

# The gates write into the checkout and install packages: refuse to run on a developer machine, where that
# would dirty a real working tree.
bk_require_buildkite() {
  if [[ "${BUILDKITE:-}" != "true" ]]; then
    bk_err "these steps run only inside a Buildkite job (BUILDKITE=true); refusing to modify this checkout"
    exit 1
  fi
}

bk_require_tools() {
  local tool missing=0
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      bk_err "required tool '$tool' is not on PATH (CI image prerequisite, see .buildkite/README.md)"
      missing=1
    fi
  done
  return "$missing"
}

# bk_require_py_module <module> <distribution>: the image's python3 can import <module> (what the GH ubuntu
# runner's system python gave the gate). The module name is an argument, never spliced into code.
bk_require_py_module() {
  local mod="$1" dist="$2"
  if [[ ! "$mod" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]]; then
    bk_err "bk_require_py_module: '$mod' is not a Python module name"
    return 1
  fi
  bk_require_tools python3 || return 1
  if ! python3 -c 'import importlib, sys; importlib.import_module(sys.argv[1])' "$mod" >/dev/null 2>&1; then
    bk_err "python3 cannot import '$mod' (${dist}): CI image prerequisite missing, see .buildkite/README.md"
    return 1
  fi
}

bk_assert_node_major() {
  bk_require_tools node || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [[ "$major" != "$BK_REQUIRED_NODE_MAJOR" ]]; then
    bk_err "Node ${BK_REQUIRED_NODE_MAJOR}.x is required; found major ${major}"
    return 1
  fi
  printf 'node %s, npm %s\n' "$(node --version)" "$(npm --version 2>/dev/null || printf 'absent')"
}

# The checkout may be shallow and may lack tags and the PR base branch. Several gates (version-sync,
# context-integrity, node-suites, the ratchets) read history, tags or origin/<base>. Best effort, and every
# miss is a visible warning; the gates themselves fail loudly (or fall back to a full-tree scan) when the
# history they need is absent.
bk_ensure_history() {
  if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null || printf false)" == "true" ]]; then
    git fetch --quiet --no-tags --unshallow origin 2>/dev/null || bk_warn "could not unshallow the checkout; history-dependent gates may fall back or fail"
  fi
  git fetch --quiet --tags origin 2>/dev/null || bk_warn "could not fetch tags; version-sync compares against the tags present"
}

# bk_gh_env: emulate the GitHub Actions context the verbatim gates read. Exports only plain, non-secret
# values. Unknowns are exported EMPTY, which is what GH gives a gate on that event, so each gate takes its
# own documented fallback instead of silently skipping.
bk_gh_env() {
  local base="" base_sha="" head_sha
  head_sha="$(git rev-parse HEAD)"
  local is_pr=false
  if [[ -n "${BUILDKITE_PULL_REQUEST:-}" && "${BUILDKITE_PULL_REQUEST}" != "false" ]]; then is_pr=true; fi

  PR_BASE_SHA="" PR_HEAD_SHA="" MERGE_BASE_SHA="" PUSH_BEFORE_SHA="" BASE_REF=""
  if [[ "$is_pr" == "true" ]]; then
    base="${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-}"
    if [[ -n "$base" ]] && git check-ref-format --branch "$base" >/dev/null 2>&1; then
      if ! git rev-parse --verify --quiet "refs/remotes/origin/${base}^{commit}" >/dev/null; then
        git fetch --quiet --no-tags origin "+refs/heads/${base}:refs/remotes/origin/${base}" 2>/dev/null || true
      fi
      base_sha="$(git rev-parse --verify --quiet "refs/remotes/origin/${base}^{commit}" || true)"
      BASE_REF="$base"
    else
      bk_warn "PR base branch is empty or not a valid ref name; gates fall back to their no-base behaviour"
    fi
    PR_BASE_SHA="$base_sha"
    PR_HEAD_SHA="${BUILDKITE_COMMIT:-$head_sha}"
    GITHUB_EVENT_NAME="pull_request"
  else
    # GH `push.before` is the previous main tip. Buildkite has no before-sha. A merge commit's first parent
    # is exactly the pre-merge main; for any other commit the base is unknown and stays empty.
    if [[ "$(git rev-list --parents -n1 HEAD | awk '{print NF-1}')" -ge 2 ]]; then
      PUSH_BEFORE_SHA="$(git rev-parse HEAD^1)"
    fi
    GITHUB_EVENT_NAME="push"
  fi
  # BASE_SHA is ratchet.yml's `pull_request.base.sha || merge_group.base_sha`.
  BASE_SHA="${PR_BASE_SHA:-$MERGE_BASE_SHA}"
  GITHUB_REPOSITORY="$BK_REPO_SLUG"
  bk_mktemp_dir RUNNER_TEMP
  GITHUB_WORKSPACE="$BK_REPO_ROOT"
  GITHUB_STEP_SUMMARY="$RUNNER_TEMP/step-summary.md"
  : >"$GITHUB_STEP_SUMMARY"
  GITHUB_OUTPUT="$RUNNER_TEMP/step-output.txt"
  : >"$GITHUB_OUTPUT"
  export PR_BASE_SHA PR_HEAD_SHA MERGE_BASE_SHA PUSH_BEFORE_SHA BASE_SHA BASE_REF GITHUB_EVENT_NAME GITHUB_REPOSITORY RUNNER_TEMP \
    GITHUB_WORKSPACE GITHUB_STEP_SUMMARY GITHUB_OUTPUT
  printf 'gh-env: event=%s base=%s before=%s\n' "$GITHUB_EVENT_NAME" "${PR_BASE_SHA:-(none)}" "${PUSH_BEFORE_SHA:-(none)}"
}

# bk_py_venv [pip-spec...]: a job-local venv first on PATH, so `python`, `python3` and `pip` are the venv's
# (what `setup-python` gave the GH job; the verbatim `pip install ...` gates then install into it). With
# package arguments it installs them too. Installs need PyPI egress (pypi.org, files.pythonhosted.org).
bk_py_venv() {
  local venv
  bk_require_tools python3 || return 1
  bk_mktemp_dir venv
  python3 -m venv "$venv/v"
  PATH="$venv/v/bin:$PATH"
  export PATH
  if [[ "$#" -gt 0 ]]; then
    python3 -m pip install --quiet --disable-pip-version-check "$@"
  fi
}

# bk_gate_flags <file>: the bash flags GH used for the step: `-e` by default, `-eo pipefail` when the step
# declared `shell: bash` (recorded in the gate's header as `# gh-shell: bash`).
bk_gate_flags() {
  if grep -qx '# gh-shell: bash' "$1"; then printf -- '-eo pipefail'; else printf -- '-e'; fi
}

# bk_gate_header <file> <key>: the values of the `# <key>: ` lines in the gate's LEADING comment block.
bk_gate_header() {
  awk -v k="# $2: " '!/^#/ { exit } index($0, k) == 1 { print substr($0, length(k) + 1) }' "$1"
}

# bk_gate_workdir <file> <var>: the directory the gate runs in, stored in <var>: the repo root, or the GH
# `working-directory` the header records. It must be a relative path to an existing directory that stays
# inside the checkout after symlinks resolve; anything else refuses the gate (returns 1).
bk_gate_workdir() {
  local __wd __dir __root
  __wd="$(bk_gate_header "$1" gh-working-directory)"
  __root="$(cd "$BK_REPO_ROOT" && pwd -P)"
  if [[ -z "$__wd" ]]; then
    printf -v "$2" '%s' "$__root"
    return 0
  fi
  if [[ "$__wd" == /* || "/$__wd/" == */../* || "$__wd" == *$'\n'* || ! -d "$__root/$__wd" ]]; then
    return 1
  fi
  __dir="$(cd "$__root/$__wd" && pwd -P)" || return 1
  [[ "$__dir/" == "$__root/"* ]] || return 1
  printf -v "$2" '%s' "$__dir"
}

# bk_gate <label> <gate file> [advisory]: run one verbatim gate as `bash -e <file>`, in the GH working
# directory and with the step's literal GH `env:` (`# gh-env: NAME=value` header lines). Never aborts the
# step; records the verdict for bk_gates_summary. The log group is expanded when it fails.
bk_gate() {
  local label="$1" file="$2" mode="${3:-blocking}" rc=0 path dir kv
  local -a envs=()
  path="$BK_REPO_ROOT/.buildkite/gates/$file"
  if [[ ! -f "$path" ]]; then
    bk_err "gate file .buildkite/gates/$file is missing"
    _bk_failed+=("$label (gate file missing)")
    return 0
  fi
  if ! bk_gate_workdir "$path" dir; then
    bk_err "gate file .buildkite/gates/$file: gh-working-directory is not a directory inside the checkout"
    _bk_failed+=("$label (bad working directory)")
    return 0
  fi
  while IFS= read -r kv; do
    if [[ ! "$kv" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
      bk_err "gate file .buildkite/gates/$file: a gh-env header line is not NAME=value"
      _bk_failed+=("$label (bad gh-env header)")
      return 0
    fi
    envs+=("$kv")
  done < <(bk_gate_header "$path" gh-env)
  bk_section "$label"
  # shellcheck disable=SC2046 # the flags are two fixed words, split on purpose
  (
    cd "$dir" || exit 1
    env ${envs[@]+"${envs[@]}"} bash $(bk_gate_flags "$path") "$path"
  ) || rc=$?
  bk_record_gate "$label" "$rc" "$mode"
}

bk_record_gate() {
  local label="$1" rc="$2" mode="$3"
  if [[ "$rc" -eq 0 ]]; then
    _bk_passed+=("$label")
  elif [[ "$mode" == "advisory" ]]; then
    _bk_advisory+=("$label (exit $rc)")
    printf '^^^ +++\n'
    bk_warn "$label failed but is advisory on GitHub (continue-on-error); not failing the step"
  else
    _bk_failed+=("$label (exit $rc)")
    printf '^^^ +++\n'
    bk_err "$label FAILED (exit $rc)"
  fi
}

# bk_gate_fail <label>: record a blocking failure for a setup command that is not a gate file.
bk_gate_fail() { _bk_failed+=("$1"); printf '^^^ +++\n'; bk_err "$1 FAILED"; }

bk_skip() { _bk_skipped+=("$1"); bk_warn "skipped: $1"; }

bk_gates_summary() {
  local g
  if [[ -s "${GITHUB_STEP_SUMMARY:-}" ]]; then
    bk_section "step summary (what GH writes to \$GITHUB_STEP_SUMMARY)"
    cat -- "$GITHUB_STEP_SUMMARY"
  fi
  bk_section "gate summary"
  for g in "${_bk_passed[@]+"${_bk_passed[@]}"}"; do printf '  pass      %s\n' "$g"; done
  for g in "${_bk_advisory[@]+"${_bk_advisory[@]}"}"; do printf '  advisory  %s\n' "$g"; done
  for g in "${_bk_skipped[@]+"${_bk_skipped[@]}"}"; do printf '  skipped   %s\n' "$g"; done
  for g in "${_bk_failed[@]+"${_bk_failed[@]}"}"; do printf '  FAIL      %s\n' "$g"; done
  if [[ "${#_bk_failed[@]}" -gt 0 ]]; then
    printf '^^^ +++\n'
    bk_err "${#_bk_failed[@]} blocking gate(s) failed"
    exit 1
  fi
  printf 'all blocking gates passed (%s pass, %s advisory, %s skipped)\n' "${#_bk_passed[@]}" "${#_bk_advisory[@]}" "${#_bk_skipped[@]}"
}
