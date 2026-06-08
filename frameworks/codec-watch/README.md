# codec-watch

> Passive monitor for upstream codec releases that change WAVE's protocol-plane
> roadmap. Opens a sticky GitHub issue when the upstream lands a release we've
> been waiting on, so the next person to look at the codec backlog sees a real
> ping rather than having to remember.

## Why this exists

Some roadmap items are gated on **upstream releases we don't control**:

| WAVE task | Upstream gate | Why it's gated |
|---|---|---|
| Track #170 | ffmpeg 8.2 (or N-nightly enabling `--enable-libavm`) | First version with `libavm` (AV2) integrated — the WAVE transport-layer AV2 spike unblocks |

We could check by hand every week. We forget by hand every week. So we let a
GitHub Actions cron do it, scope-tight: it polls, it never commits, it never
auto-edits roadmap docs. The only output is one sticky issue per watched gate,
updated in place — no notification spam.

## Layout

```
frameworks/codec-watch/
├── README.md                       (this file)
└── scripts/
    └── check-libavm.sh             (called by the cron workflow)
```

The cron workflow lives at `.github/workflows/codec-watch-libavm.yml`. It runs
weekly (Wednesday 06:00 UTC) and on `workflow_dispatch`.

## What it does

1. Fetches the latest tag list from `https://github.com/FFmpeg/FFmpeg.git` via
   `git ls-remote --tags` — no clone, no checkout, just the SHA list.
2. Greps for any tag matching `^n8\.[2-9]` or `^n[9-9]\.` (8.2+, 9.x+).
3. Falls back to the `master` branch HEAD's `configure` script to detect when
   `--enable-libavm` becomes a real flag (currently it's not yet in upstream).
4. If either signal trips, opens or updates a sticky issue tagged
   `codec-watch:libavm` with the version + link to the upstream release notes.
5. If neither signal trips, it closes any existing sticky issue (so we don't
   carry stale "still waiting" noise) and exits 0.

## Why a sticky issue (not a PR)

The roadmap document this informs (the transport-layer roadmap, task #170) is human-owned
— closing it should happen in the context of a code change (the libavm
integration spike), not a robot edit. The sticky issue is the prompt; the
human picks it up when they're ready.

## Adding another gate

Copy `check-libavm.sh` to a new script under `scripts/`, wire a sibling
workflow under `.github/workflows/`, and add a row to the table above. The
pattern is intentionally one-workflow-per-gate so failures don't cross-block.

## Local test

```bash
bash frameworks/codec-watch/scripts/check-libavm.sh
# Exit 0  → nothing to report
# Exit 10 → 8.2+ tag found    (prints "found: n8.2-X")
# Exit 11 → libavm flag found (prints "found: libavm-flag")
```

Exit codes are deliberately distinct so the workflow can branch on cause.
