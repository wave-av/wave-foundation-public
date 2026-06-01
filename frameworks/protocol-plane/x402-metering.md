# Bridges-layer x402 Metering

How CF Containers' active-CPU pricing translates into x402 micropayments for the Bridges layer of the [Protocol Plane](README.md).

## The economic substrate

CF Containers bill for **every 10ms of active CPU** plus memory + disk + network egress. Active-CPU pricing means a tenant only pays while their protocol stream is actively flowing — idle tenants cost nothing.

This is the unlock for x402 pay-per-use at the bridge layer: per-stream metering aligns 1:1 with the underlying cost driver. There's no spread or staircase pricing because the underlying cost is already linear.

## Meter shape

The Go control plane adapter in every bridge container (SRT, NDI, OMT, ffmpeg, etc) ticks an internal stopwatch while protocol traffic flows. Every 10 seconds it posts:

```json
POST gateway.wave.online/v1/meter
Authorization: Bearer <container's gateway-issued JWT>
Content-Type: application/json

{
  "token_sub": "usr_abc123",          // the consumer
  "layer": "bridges",
  "protocol": "srt",                  // or ndi/dante/omt/ffmpeg
  "kind": "active_seconds",
  "value": 9.847,                     // how much active CPU since last post
  "container_id": "ctr_def456",
  "ts": "2026-05-30T15:30:00Z"
}
```

The gateway aggregates and settles into the customer's current rail (Stripe, x402 wallet, monthly invoice).

## x402 specifics

For `act: "agent"` tokens, the bridge container also re-validates the x402 micropayment proof every 10 seconds. If the wallet balance dips below the next 10s tick's expected charge, the bridge gracefully terminates the stream with HTTP 402 Payment Required.

This is the **stream-grade** x402 pattern (continuous re-validation), distinct from the API-call x402 pattern (one-shot per request).

## Pricing table (current, subject to revision)

| Protocol | Per active-second | Tier discount available |
|---|---|---|
| SRT | $0.0001 | yes (≥10k seconds/mo) |
| NDI | $0.00015 | yes |
| OMT | $0.0001 | yes |
| ffmpeg transcode (AV1/HEVC/H.264 encode) | $0.0005 | per-codec varies |
| ffmpeg transcode (AV2 encode) | $0.0015 | premium tier (reference-encoder is slow) |
| Whisper STT filter | $0.0010 | yes |

Pricing is per-stream-second of active CPU, not per-bandwidth. Bandwidth egress passes through at CF's cost ($0.025/GB NA/EU) until the included 1TB/month is exhausted.

## Tier model

Stream-grade tenants get bulk-rate discounts for sustained high-volume usage:

- Tier 1 (default): list rate above
- Tier 2 (commit ≥100k active-seconds/mo): 20% off
- Tier 3 (commit ≥1M active-seconds/mo): 40% off
- Enterprise (committed annual): negotiated

Tier promotion is automatic based on the trailing-30-day usage from the meter post-back stream.

## Implementation notes

1. **Heartbeat shape**: the 10-second cadence is the cost-vs-precision tradeoff. Faster (1s) is more accurate but burns more Worker invocations on the gateway side. Slower (60s) is cheaper but creates 60s blast radius when a wallet runs dry.
2. **Failure mode**: if a meter post fails (network blip), the container caches locally and retries next cycle. The gateway de-dups by `(container_id, ts)`.
3. **Bridge container restart**: a new container instance gets a fresh gateway JWT and a fresh container_id. The active-seconds counter is per-container, so restarting doesn't double-bill.
4. **Multi-tenant container**: one container can serve multiple `token_sub` values; metering tracks per-token, not per-container.
5. **Bookkeeping reconciliation**: every hour, the gateway emits a per-`token_sub` invoice line that customer dashboards can render.

## Linked

- [Cross-layer Auth Token Model](auth-token-model.md) — where the JWT comes from
- [Protocol Plane](README.md) — the four layers
- [Pricing & Settlement Standard](../pricing/README.md) — the broader pricing framework
- [Dispatch payment-rails-contract](https://github.com/wave-av/wave-dispatch) — the cross-rail abstraction (Stripe/x402/etc)
