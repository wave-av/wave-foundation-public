# Cross-layer Auth/Token Model

How ONE token works across all four layers of the [Protocol Plane](README.md). This invariant is what makes WAVE's positioning ("the signal everywhere") economically and operationally tractable: a customer pays once, gets metered once, and consumes signal regardless of layer.

## The model

```
┌──────────────────────────────────────────────────────────────┐
│  gateway.wave.online — single token issuer                    │
│   ├─ JWT (humans, web/browser)                                │
│   ├─ x402 micropayment + scope JWT (AI agents)                │
│   ├─ device-binding token (Local Agent on workstations)       │
│   └─ partner-bootstrap token (Hardware tier)                  │
└──────────────────────────────────────────────────────────────┘
                │
   ┌────────────┼────────────┬─────────────┐
   │            │            │             │
┌──▼──────┐ ┌───▼───────┐ ┌──▼──────┐ ┌───▼───────────┐
│  EDGE   │ │ BRIDGES   │ │ LOCAL   │ │ HARDWARE      │
│ Workers │ │Containers │ │  Agent  │ │ Certified     │
└─────────┘ └───────────┘ └─────────┘ └───────────────┘

All four verify the SAME token shape (jose.JWS).
All four read the SAME scope claim (`sc`).
All four report usage to the SAME meter (`pay-per-use` rail).
All four are subject to the SAME revocation feed.
```

## Token shapes

### 1. Human JWT (web/app)

Standard OIDC. Issued by gateway after Magic-Link / SSO / passkey. Bearer in `Authorization: Bearer ...`. Short-lived (1h) with refresh.

```jwt
{
  "iss": "https://gateway.wave.online",
  "sub": "usr_abc123",
  "aud": "wave-edge",
  "exp": <epoch>,
  "iat": <epoch>,
  "sc": ["streams:read","streams:write","clips:read"],
  "act": "human",
  "tier": "pro"
}
```

### 2. Agent x402 token

Same shape, plus x402 settlement assertion:

```jwt
{
  ...as above,
  "act": "agent",
  "x402": {
    "network": "base",
    "settled_in": "0xabc..."         // tx hash of the micropayment
  }
}
```

The bridges layer checks the x402 assertion every N seconds of active CPU and re-prompts if missing — that's how active-CPU-pricing pay-per-use metering works for agents.

### 3. Device-binding token (Local Agent)

Bound to a device fingerprint (MAC + OS + hostname hash). 24h rotating, stored in OS keychain. Used by `wave-agent` to authenticate registrations of local NDI/Dante sources to the gateway.

```jwt
{
  ...as above,
  "act": "local_agent",
  "device": {
    "fingerprint": "sha256:abc...",
    "os": "darwin",
    "hostname_hash": "sha256:def..."
  }
}
```

When a cloud-side container wants to consume a registered source, it includes both its own scope JWT AND the device-binding token in the proxy handshake (mutual-handoff pattern).

### 4. Partner bootstrap token (Hardware)

Embedded in WAVE Certified hardware images / firmware at provisioning. Lower scope (just `streams:write` for the device's own output), rotated quarterly via OTA.

```jwt
{
  ...as above,
  "act": "hardware",
  "hardware": {
    "model": "birddog-encoder-x1",
    "serial": "BDX1-001-abcd1234",
    "certified_via": "wave-certify://sha256:..."  // hash of cert artifact
  }
}
```

## What's invariant across layers

| Property | Edge | Bridges | Local | Hardware |
|---|---|---|---|---|
| Same `iss` | ✓ | ✓ | ✓ | ✓ |
| Same `aud` (gateway audience) | ✓ | ✓ | ✓ | ✓ |
| Same `sc` claim semantics | ✓ | ✓ | ✓ | ✓ |
| Same revocation feed | ✓ | ✓ | ✓ | ✓ |
| Same meter post-back | ✓ | ✓ | ✓ | ✓ |
| Same `exp` enforcement | ✓ | ✓ | ✓ | ✓ |

## What's per-layer

| Property | Edge | Bridges | Local | Hardware |
|---|---|---|---|---|
| Token issuance trigger | Magic-Link / SSO | x402 settlement | Device-binding flow | Partner-bootstrap flow |
| Token TTL | 1h | 1h | 24h | 90d |
| Renewal method | refresh token | next x402 micropayment | rotating bootstrap | OTA rotation |
| Storage | secure cookie | wallet keystore | OS keychain | TPM / secure element |
| Per-stream check cadence | every request | every 10s active | every minute | every 5 min |

## Meter post-back

All four layers POST to `gateway.wave.online/v1/meter` with the same shape:

```json
{
  "token_sub": "usr_abc123",
  "layer": "bridges",
  "protocol": "ndi",
  "kind": "active_seconds",
  "value": 13.5,
  "ts": "2026-05-30T15:30:00Z"
}
```

The gateway settles based on the `act` claim:
- `human` → charge their card / Stripe customer
- `agent` → debit x402 wallet
- `local_agent` → roll up to the human (device-binding has owner_sub)
- `hardware` → roll up to the partner contract

## Scope rule examples

```
streams:read       — pull a stream as consumer
streams:write      — push a stream as producer
clips:read         — fetch a clip
clips:write        — create a clip
bridges:transcode  — invoke the ffmpeg/AV2 container
agents:invoke      — call an AI tool over the bridge layer
admin:*            — administrative ops (very restricted)
```

Scope rules are evaluated by the gateway BEFORE the request reaches the layer. The layer trusts the scope claim — there's no per-layer ACL.

## Revocation

A revoked sub or jti goes into the gateway's revocation Bloom filter, distributed to:

- Edge: KV namespace `revoked_tokens`, checked per-request
- Bridges: container fetches every 60s
- Local Agent: pulls every 5 min
- Hardware: pulls every hour (less time-sensitive, longer TTL)

Bloom is fine because revocation is rare — false positives just trigger a real DB check.

## Why this is the WAVE moat

Anyone can build edge-only auth (Cloudflare Access, Auth0). Anyone can build bridges-only meter (per-job stripe). Anyone can build a local agent (Tailscale-like). What's hard is making one token + one meter + one scope rule engine fluent across all four AT THE SAME TIME. That's the moat — and it requires owning every layer's identity model, which we now do.

## Linked

- [Protocol Plane](README.md) — the 4 layers this token spans
- [Pricing & Settlement Standard](../pricing/README.md) — how charges flow from meter to invoice
- [WAVE Edge Plane roadmap](https://github.com/wave-av/wave-foundation/issues/95) — O-series products on top of this
