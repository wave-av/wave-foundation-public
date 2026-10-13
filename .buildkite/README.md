# wave-foundation-public on Buildkite (shadow mode)

This directory ports this repository's own GitHub Actions gates to Buildkite. Nothing under `.github/`
changes, and the GitHub workflows stay the gate until the Buildkite pipeline has been green for a soak
period. No Buildkite pipeline exists for this repository yet; creating one is a separate, reviewed operator
step (see "Fork pull requests").

## Ownership: this directory is maintained here, not synced

Most of this repository is published from a private source by an allowlist sync. `.buildkite/` is not on
that allowlist and must not be: the private source has its own `.buildkite/` for its own pipeline, and the
sync copies paths one to one, so a synced copy would overwrite this pipeline's settings with the private
repository's. This directory is therefore owned by this repository, like `.github/workflows/lint.yml` and
`.github/workflows/public-repo-guard.yml`. The private mirror verifier lists it as public-only so it is not
reported as drift.

## Fork pull requests are never built

Fork PRs never run on this pipeline's agents. The agents are self-hosted, and an uploader step runs the
checked-in `.buildkite/wave-ci.sh` before anything else, so a fork build would run fork-controlled code on
them. The fences, in order:

1. **The pipeline setting `build_pull_request_forks: false`.** This is the one that matters: with it off,
   Buildkite never creates a build for a fork PR. The operator tool that creates pipelines (wave-ci RUN-229)
   sends it explicitly, refuses before any write if its payload has it on, reads the pipeline back after the
   write and fails if Buildkite turned it on, and its verify mode fails on a pipeline where someone switched
   it on by hand. At the pinned commit that tool still refuses every public repository outright, so this
   pipeline cannot be created until the tool gains a reviewed public-repository path.
2. **No fork-approval path.** The renderer can build a fork PR that a maintainer labels `ci:approved`
   (secret-free steps, but still on the self-hosted queue). That path is not used for this repository: no
   handler that creates such builds is enabled, and none may be. A fork PR's checks stay on GitHub-hosted
   runners.
3. **A tripwire in `scripts/lib/common.sh`.** Every step refuses to run on a PR whose head repository is not
   this one. It is not a boundary (a fork controls its own copy of that file); it exists so that a
   misconfigured pipeline shows up as a red first step on a benign fork PR, never as a quiet green build.

No step of this pipeline holds a credential, so there is nothing for a build to leak either way.

## Layout

| path | role |
|---|---|
| `pipeline.yml`, `wave-ci.sh`, `wave-ci.json` | The wave-ci template form: the thin uploader and the fixed shim (byte-identical to the template kit at the pin), and the settings: template `custom`, `wave_ci` pinned to `296cc0cf4faf1f06d0acd4c2a767d6c111d2adf3`, `visibility: public`. |
| `wave-ci.deferred.json` | NOT rendered. Every job with no running step: a parked step entry (ready to move back), the GH schedule leg, the parked jobs by class, and the reusable-workflow jobs. |
| `scripts/<step>.sh` | One script per Buildkite step. Each sets up its tools, then runs its gates. `pr-metadata.sh` is written but parked. |
| `scripts/lib/common.sh` | Strict mode, credential hygiene, the fork tripwire, the GH-context emulation (`bk_gh_env`), the gate runner and summary. |
| `scripts/lib/rubocop.sh` | The sha256-pinned rubocop gem closure for the ruby ratchet. |
| `gates/*.gate` | The VERBATIM `run:` bodies of the GH steps being replaced, one file per step, named `<workflow>.<job>.<nn>-<step>.gate`. |

11 steps run (the cap is 20 per pipeline file). Each runs every gate even after a failure and prints a summary.

## Why the gates are copies, and why `.gate`

A gate that runs the same bytes as the GH step is a parity claim that can be checked. Each file header names
the workflow, job and step it came from and the commit it was taken at. They run as `bash -e <file>` (the GH
default shell), or `bash -eo pipefail` for a step that set `shell: bash`. They are fragments of YAML-embedded
shell, so they use the `.gate` extension (not linted as standalone scripts, not read as pipeline files). To
refresh one, copy the step's `run:` body from the workflow unchanged. A `# gh-env: NAME=value` header line is
a literal `env:` entry of the step; a `# gh-env-src:` line records an expression value the step script
supplies (or, for GUARD_PRIVATE_REPOS, cannot supply; see below).

## Parity map (all 18 workflows, 53 jobs)

| GH workflow | job | GH trigger | Buildkite | status |
|---|---|---|---|---|
| self-check.yml | secret-scan | PR, push main, merge_group | `self-check-secret-scan` | ported |
| self-check.yml | file-size | PR, push main, merge_group | `self-check-size` | ported |
| self-check.yml | context-integrity | PR, push main, merge_group | `self-check-size` | ported |
| self-check.yml | skill-validate | PR, push main, merge_group | `self-check-python` | ported |
| self-check.yml | version-sync | PR, push main, merge_group | `self-check-python` | ported |
| self-check.yml | claude-api-shape | PR, push main, merge_group | `self-check-python` | ported |
| self-check.yml | gate-registry-drift | PR, push main, merge_group | `self-check-python` | ported |
| self-check.yml | status-context-conformance | PR, push main, merge_group | `self-check-node` | ported |
| self-check.yml | product-registry-drift | PR, push main, merge_group | `self-check-node` | ported |
| self-check.yml | capabilities-honesty | PR, push main, merge_group | `self-check-node` | ported |
| self-check.yml | gate-self-tests | PR, push main, merge_group | `gate-self-tests` | ported |
| self-check.yml | node-suites | PR, push main, merge_group | `node-suites` | ported |
| lint.yml | shellcheck | PR (push: master only, so never on main) | `lint` (pr_only) | ported |
| lint.yml | ruff | PR (push: master only, so never on main) | `lint` (pr_only) | ported |
| pinact.yml | pinact | PR, push main, merge_group | `pinact` | ported |
| public-repo-guard.yml | guard | PR, push main, dispatch | `public-repo-guard` | ported (one rule unarmed, see below) |
| ratchet.yml | shell | PR, dispatch, merge_group | `ratchet` (pr_only) | ported |
| ratchet.yml | python | PR, dispatch, merge_group | `ratchet` (pr_only) | ported |
| ratchet.yml | cpp | PR, dispatch, merge_group | `ratchet` (pr_only) | ported |
| ratchet.yml | rust | PR, dispatch, merge_group | `ratchet` (pr_only) | ported |
| ratchet.yml | go | PR, dispatch, merge_group | `ratchet` (pr_only) | ported |
| ratchet.yml | ruby | PR, dispatch, merge_group | `ratchet` (pr_only) | ported |
| zizmor.yml | zizmor | PR, push main, merge_group | `zizmor` | ported (offline audits, see below) |
| semantic-pr.yml | validate-title | PR | `pr-metadata` | deferred: needs host-fetched PR title/body |
| governance-enforce.yml | enforce | PR, push main | none | parked: private npm package (GitHub Packages E403; self-hosted registry not live) |
| release.yml | classify | tag v* | none | parked: publish |
| release.yml | major-tag-safety | tag v* | none | parked: publish |
| release.yml | release | tag v* | none | parked: publish |
| release.yml | sbom | tag v* | none | parked: publish |
| changelog-unreleased.yml | refresh | push main | none | parked: publish (opens a PR with a bot token) |
| scorecard.yml | analysis | push main, weekly cron, branch_protection_rule | none | parked: publish (results + SARIF upload); schedule in `deferred_schedules` |
| bot-review-gate.yml | resolve | PR, review and comment events, workflow_call | none | parked: event bot |
| bot-review-gate.yml | tally | as above | none | parked: event bot |
| bot-review-gate.yml | liveness | as above | none | parked: event bot |
| bot-review-gate.yml | verdict | as above | none | parked: event bot |
| pr-agent.yml | pr_agent | PR, issue_comment | none | parked: event bot (posts to the PR, needs a model credential) |
| checks.yml | checks, claude-config, skill-validate, claude-api-shape, claude-api-cache, verify-routes, voice, billing-contract, meter-registry, dependency-review, pr-body, changelog, ci-efficiency (13 jobs) | workflow_call only | none | library: never runs on this repo's events |
| image-content-gate.yml | gate | workflow_call only | none | library |
| io-triage.yml | triage | workflow_call only | none | library |
| reusable-bot-token.yml | generate | workflow_call only | none | library |
| reusable-changelog.yml | changelog | workflow_call only | none | library |

Totals: 23 ported in 11 steps, 1 deferred (step written), 12 parked (6 publish, 5 event bot, 1 private
registry), 17 library. Nothing is dropped.

"Library" jobs belong to reusable workflows (`on: workflow_call` only). Nothing in this repository calls them,
so GitHub never runs them on this repository's own events either; other repositories call them on their own
runners. There is nothing for this pipeline to run in their place.

## Differences from GH, on purpose

- **Triggers.** No workflow here has `on.paths`, so no step is path-filtered. `lint` and `ratchet` are
  `pr_only`, matching GH: lint.yml's push trigger names `master`, which this repository does not use, and
  ratchet.yml has no push trigger. `merge_group` and `workflow_dispatch` have no Buildkite counterpart; a
  manual build of `main` runs every non-PR step.
- **Toolchain.** Node 24 for every node gate, as on GH. GH's `setup-python` becomes a job-local venv first on
  PATH, so the verbatim `pip install pyyaml` / `pip install ruff` gates install into it (PyPI egress).
  shellcheck, cppcheck, gitleaks 8.30.1 and ripgrep come from the CI image (same versions GH pins or the
  ubuntu-24.04 runner ships), replacing GH's `sudo`/`apt-get` install steps; the guard step fails, rather
  than scans, if the image's gitleaks is not 8.30.1. pinact 4.0.0 and zizmor 1.25.2 are downloaded per job
  from their GitHub releases and checked against pinned sha256 digests. The ruby leg installs a sha256-pinned
  rubocop closure instead of GH's unpinned `gem install rubocop`. clippy ships in the image.
- **zizmor runs offline audits only.** On GH this mirror's audit falls back to the repo-scoped
  `github.token` and also runs the online audits (impostor-commit, known-vulnerable actions). This pipeline
  holds no GitHub token, so the step runs `--no-online-audits` and lists the online tier as skipped on every
  build.
- **pinact `--verify` is anonymous.** GH passes `github.token`; here the GitHub API is called without one
  (60 requests/hour per egress IP). A rate-limited run fails the gate, never passes.
- **public-repo-guard: the private-repo-name rule is not armed.** GH injects `GUARD_PRIVATE_REPOS` from an
  org-level variable. That list is not public, so it cannot be written into this repository, and the
  pipeline has no non-public channel for it yet. `content-policy.sh` skips that one rule when the variable is
  unset (its documented behaviour) and the step records the skip. gitleaks and every other rule run as on GH.
- **Every ratchet leg is a no-op here, as on GH.** The ratchet scripts are not published to this mirror, so
  each verbatim gate prints its "absent (public mirror)" notice and exits 0. The tool installs still run.
- `harden-runner` steps are dropped (the guest firewall replaces them); checkouts are the agent's.

## Red on GitHub main today

On `main` at d922e69 (2026-10-08) GitHub reports `self-check / gate-self-tests` and `zizmor` as failed;
every other ported job passed. The gates here are verbatim copies, so the soak should show the same red; a fix
belongs in the workflow or the files it checks, not in these copies.

## Credentials

None. No step declares a secret and no secrets-allowlist row is needed. Decisions that would add one, each
for the repository owner: a read-only GitHub token for `zizmor` (online audits) and `pinact` (`--verify`
without the anonymous rate limit); a non-public channel for `GUARD_PRIVATE_REPOS`; and, when the self-hosted
npm registry is live, whatever read credential `governance-enforce` needs.
