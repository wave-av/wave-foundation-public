# agent-lease — concurrent-agent coordination

A lightweight, git-native lease so multiple Claude sessions/agents working the same repo at once stop
**colliding silently**. It turns "two sessions independently started the same work" into an explicit,
checkable signal you can see *before* you start.

## Why this exists

WAVE repos are worked by several concurrent sessions. With no coordination they collide:

- two release PRs for the same version (a real near-miss: a duplicate `v1.7.0` cut),
- two branches editing the same file,
- one session retargeting a PR base and stranding another's stacked PR.

A lease lets a session **announce** what it's holding and lets the next session **check** first.

## How it works

A lease is a git ref `refs/agent-leases/<slug>` created via the GitHub API. **Ref creation is atomic** —
`POST /git/refs` returns `422` if the ref exists — so two agents racing the same claim can't both win.
The ref points at an annotated tag object whose message carries the metadata (agent, branch, PR, timestamp,
TTL), so `list` shows holders, age, and expiry. The custom `refs/agent-leases/*` namespace is **not**
fetched by `git fetch` by default, so leases never clutter anyone's branch or tag lists.

It is a **coordination aid, not a hard mutex.** A lease past its TTL (default 120 min) is auto-pruned on
the next `claim`/`list`. A live lease means "coordinate before overlapping" — always `release` when done.

## Use

```bash
L=.foundation/frameworks/agent-lease/lease.sh   # path after consume.sh vendors it (or frameworks/... in-repo)

bash "$L" list                                  # what is anyone working right now?
bash "$L" claim feat/my-thing --pr 123 --note "billing seam"   # exit 3 if already held
# ... do the work ...
bash "$L" release feat/my-thing

bash "$L" mine        # leases you hold
bash "$L" prune       # delete expired leases
bash "$L" doctor      # local self-check (no API writes)
```

Exit codes: `0` ok · `2` usage/env · `3` lease held by someone else (branch on this in scripts).

Env: `LEASE_AGENT_ID` (default `$USER@$(hostname -s)`), `GH_REPO` (default: `gh`-detected). Requires an
authenticated `gh` and `python3`.

## Suggested workflow integration

Before starting overlapping work (a release cut, a multi-file refactor, a PR retarget), `claim` the
branch; if it returns exit 3, read the holder and coordinate instead of racing. `scripts/release.sh`'s
duplicate-release guard is the same idea specialized to releases; this generalizes it to any branch.
