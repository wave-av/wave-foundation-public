# Bridges-layer Observability

Structured logs, Sentry error capture, and metric emission for the CF Containers running the Bridges layer of the [Protocol Plane](README.md).

## Constraints

CF Containers run a custom Linux env with limited package availability. Two constraints shape the design:

1. **Sentry SDK in-container is heavyweight** — adds 50MB+ to image, slow cold start. Avoid.
2. **Outbound Workers** (the Container → Worker hostname-binding pattern, GA 2026-03-26) lets a container call back into a sidecar Worker via plain HTTPS — ideal for forwarding telemetry without an embedded SDK.

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│  Bridge Container (libsrt / NDI Library / DAL / ffmpeg)  │
│  ┌─────────────────────────────────────────────────┐     │
│  │ Go adapter — structured slog to stdout         │     │
│  │ Anomaly hook → POST to outbound:obs-sidecar    │     │
│  └─────────────────────────────────────────────────┘     │
└─────────────────────┬─────────────────────────────────────┘
                      │ Outbound Workers binding
                      ▼
┌──────────────────────────────────────────────────────────┐
│ wave-obs-sidecar (Worker)                                │
│  ┌────────────────┐  ┌──────────────────┐               │
│  │  Sentry SDK    │  │ structured-log   │               │
│  │  forwarder     │  │ index → R2       │               │
│  └────────────────┘  └──────────────────┘               │
└──────────────────────────────────────────────────────────┘
       │                            │
       ▼                            ▼
   Sentry DSN              R2 bucket logs/<date>/...
```

The sidecar Worker is the only place the Sentry SDK lives. The container ships zero MB of SDK code. Logs route via `outbound.host=obs-sidecar` (configured in `wrangler.toml`).

## Log shape

The Go adapter uses `log/slog` with the JSON handler. Every line includes:

```json
{
  "time": "2026-05-30T15:30:00.123Z",
  "level": "INFO|WARN|ERROR",
  "msg": "...",
  "service": "wave-srt-bridge",          // or wave-ndi-bridge, etc
  "protocol": "srt",
  "container_id": "ctr_abc123",
  "token_sub": "usr_xyz",                // when handling a tenant request
  "trace_id": "abc...",                  // W3C traceparent (when distrib trace flows in)
  "span_id": "def..."
}
```

Required fields: `time`, `level`, `msg`, `service`, `protocol`. Everything else is optional / context-dependent.

## Error capture

When the adapter catches an actionable error:

```go
logger.Error("srt handshake failure",
    "err", err,
    "remote_addr", remote.String(),
    "session_id", sess.ID,
    "wave.sentry.capture", true)  // signals sidecar to forward to Sentry
```

The `wave.sentry.capture` boolean is the routing hint. Sidecar inspects all incoming log lines and forwards `level=ERROR` + `wave.sentry.capture=true` to Sentry.

This avoids noisy capture (everything that logs at ERROR isn't necessarily Sentry-worthy — e.g., a 502 from a misbehaving upstream is a metric, not a Sentry issue).

## Metrics

Counter + histogram metrics are emitted as structured log lines with a special `metric` key:

```json
{
  ...standard fields,
  "metric": {
    "name": "srt_bytes_in",
    "kind": "counter",
    "value": 13456
  }
}
```

The sidecar aggregates and exports to Cloudflare Workers Analytics Engine (free at moderate volume) and optionally to PostHog for business-side metrics.

## Container ID lifecycle

`container_id` is assigned by the CF Containers control plane at container start. The Go adapter reads it from `/proc/1/cpuset` (CF Containers stuffs it there) and includes it in every log line. When the container is replaced, the ID changes — analyzers join via `trace_id` for cross-container traces, not `container_id`.

## SSH-into-live debugging

CF Containers GA shipped SSH support (2026-03-12). For deep debugging of a stuck stream:

```bash
wrangler containers shell ctr_abc123
```

Drops you into the running container with the standard busybox toolchain. Use sparingly — every shell session is auditable in CF dashboard.

## Per-spoke Sentry projects

Per the existing [Observability framework](../observability/README.md), each spoke has its own Sentry project (`wave-srt-bridge`, `wave-ndi-bridge`, etc). The sidecar Worker for each bridge container has its own `SENTRY_DSN` env var so cross-spoke noise stays separated.

## Linked

- [Observability framework](../observability/README.md) — the broader standard
- [Auth Token Model](auth-token-model.md) — token_sub field semantics
- [x402 Metering](x402-metering.md) — metric stream for billing aggregation
