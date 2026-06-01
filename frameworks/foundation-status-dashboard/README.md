# Foundation Status Dashboard

A Grafana dashboard that visualizes the foundation's health metrics in real time. Built on the `.dogfood-metrics.ndjson` ledger (PR F) + CI trace IDs (PR AO).

## What it shows

Eight panels, organized into three rows:

### Row 1 — Coverage

| Panel | Source | Insight |
|-------|--------|---------|
| Gates passed (24h) | `pass:fail` ratio from metrics ledger | Daily health snapshot |
| Gate trend (30d) | `pass` over time per gate | Catches regressions |
| Held-by-design count | `hold:*` from metrics | Open-core hold count + spend-authority warn-state |

### Row 2 — Performance

| Panel | Source | Insight |
|-------|--------|---------|
| p50 / p95 gate duration | `duration_ms` per gate | Catches slow gates before they timeout in CI |
| Slowest 10 gates | grouped by `gate` | Where to invest in fast/full splits |

### Row 3 — Improvement loop

| Panel | Source | Insight |
|-------|--------|---------|
| Improvement queue depth | `docs/improvement-queue.md` line count | Catches accumulation |
| Findings auto-queued (7d) | improvement-loop channel events | Validates loop is actually feeding forward |
| Promote/deprecate proposals (30d) | gate-promote-deprecate analyzer | Validates lifecycle automation |

## Setup

Two ways to import:

### Option 1 — Grafana Cloud (recommended)

```bash
# 1. Grafana Cloud account (free tier covers typical foundation scale)
# 2. Create a Loki datasource pointed at where you ship .dogfood-metrics.ndjson
# 3. Import the dashboard JSON
gh release download --repo wave-av/wave-foundation --pattern "foundation-status-dashboard.json"
# then in Grafana UI: Dashboards → Import → upload JSON
```

### Option 2 — Self-host Grafana

```bash
docker run -d \
  -p 3000:3000 \
  -v $(pwd)/frameworks/foundation-status-dashboard/grafana-dashboard.json:/etc/grafana/provisioning/dashboards/foundation.json \
  grafana/grafana:11.4.0
```

## Data flow

```text
scripts/dogfood.sh
  └─► .dogfood-metrics.ndjson  (per-machine; gitignored)
      └─► [your ship mechanism: Vector, Promtail, Fluent Bit, scripts/improvement-loop/]
          └─► Loki (or similar) ←──► Grafana dashboard
```

The foundation does NOT ship a hosted Loki — that's per-consumer. The dashboard JSON expects a Loki datasource named `loki-dogfood` by default; rename via the imported dashboard's variables panel if yours is different.

## What it does NOT cover

This dashboard is foundation-self-health. It does NOT cover:

- Per-spoke product metrics (use Sentry + PostHog per `frameworks/observability/`)
- Cost (use the per-layer ledger in `frameworks/cost-management/`)
- Customer-facing SLOs (per-consumer dashboard)
- Synthetic monitoring (Checkly / Better Uptime per consumer)

It's the diagnostic for "is wave-foundation itself healthy" — runtime visibility complementing the dogfood CI gate.

## Customization

The dashboard JSON is a starting point. Common per-org tweaks:

- Change the time range default from 24h → 7d (most ops teams prefer weekly cadence)
- Add a slack-webhook alert when `held > 5` for > 24h (catches stalled open-core publish backlog)
- Add a per-host row (`HOST_NAME` field in metrics) if you run dogfood on multiple machines
- Filter `branch` to exclude `feat/*` if PR-test runs are noisy

## Cross-references

- [`scripts/dogfood.sh`](../../scripts/dogfood.sh) — emits the metrics this dashboard visualizes
- [`rules/dogfood-metrics.md`](../../rules/dogfood-metrics.md) — schema + privacy posture
- [`frameworks/improvement-loop/README.md`](../improvement-loop/README.md) — what feeds improvements into the queue
- [`scripts/gate-promote-deprecate.sh`](../../scripts/gate-promote-deprecate.sh) — lifecycle analyzer feeding the bottom row
- [`frameworks/observability/comparison-matrix.md`](../observability/comparison-matrix.md) — Grafana Cloud is the Tier-2 default
