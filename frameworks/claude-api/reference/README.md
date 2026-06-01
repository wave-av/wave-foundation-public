# Pinned Anthropic docs reference (offline backing store)

Backs `frameworks/claude-api/` with the Anthropic doc pages the standard cites. The raw `.md`
pages are **not committed** (~188 files / 5.5 MB of third-party docs that rot). They are reproducible:

- **Web** — run `../refresh-docs.sh` to repopulate from `https://platform.claude.com` (`.md`),
  driven by `llms.txt`. See `PIN.txt` for the pinned scrape date.
- **Local/offline** — last scrape cached at `/tmp/claude-docs-snapshot`; can be tarred to Studio
  for air-gapped use.

`../COVERAGE.md` maps the full Anthropic surface to covered / N-A / TODO; this dir is the offline
backing store, refreshed on demand.

## Automated drift watch (CI)

`.github/workflows/claude-docs-refresh-weekly.yml` re-runs `../refresh-docs.sh` every Tuesday and
opens a sticky issue when either:

- **Reproducibility regresses** — the scrape pulls fewer than `MIN_PAGES` (Anthropic moved/renamed
  the docs surface or `llms.txt` changed), so `refresh-docs.sh` needs updating; or
- **The pin goes stale** — `PIN.txt`'s `scraped_utc` is older than `STALE_DAYS`, so the standard may
  cite drifted guidance.

It never commits the pages (FIDELITY). Actually refreshing is a human step: run `refresh-docs.sh`,
read the diff, update the standard + `PIN.txt`.

**Hosting (web + Studio).** The pages are reproducible, so "hosting" is caching, not publishing:
- **Studio / air-gapped** — `tar czf claude-docs.tgz reference/` after a refresh and copy to Studio
  (`scp` over Tailscale); local agents read it offline. Re-tar on each refresh.
- **Web** — if a browsable mirror is wanted, serve `reference/` as static files from any host; the
  weekly workflow is the freshness signal that tells you when to re-publish.
