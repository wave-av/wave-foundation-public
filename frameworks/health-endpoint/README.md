# WAVE Health-Endpoint Standard

> One `/health` JSON shape for every edge worker — consumed, not copied. Helper:
> [`health.ts`](./health.ts). The shape was independently hand-rolled across all
> 7 edge workers (bridge / realtime / omt / dante / ndi / moq / dispatch); this is
> the single source of truth they import instead.

## The contract

Every WAVE worker answers `GET /health` with this exact JSON object:

```json
{ "ok": true, "service": "wave-dispatch", "layer": "edge", "version": "1.7.0" }
```

`content-type: application/json`, HTTP `200`. The shape is stable — uptime monitors
and the cross-layer discovery registry parse it, so fields are append-only.

| Field | Meaning |
|---|---|
| `ok` | Always `true` while the worker is serving. This is **liveness**, not deep readiness — it must not probe downstream deps (those belong on a separate `/status` route so `/health` stays cheap for high-frequency monitors). |
| `service` | The worker's repo slug, e.g. `"wave-dispatch"`. Makes a health hit attributable by service without tag-spelunking. |
| `layer` | The [protocol-plane](../protocol-plane/README.md) layer the worker sits on. Edge workers report `"edge"`; the same helper serves `"bridges"`, `"local"`, etc. |
| `version` | Build / foundation pin (e.g. a git SHA or the consumed foundation tag). `"unknown"` when not wired to a build var. |

## Why a helper

Seven edge workers each wrote their own `/health` responder. Some returned plain
`"ok"` text, some a JSON object, with no shared field set — so a monitor couldn't
rely on one shape across the fleet. One helper fixes that: change the contract in
one place, every worker that consumes it stays in sync.

## Zero-dependency, edge-safe

The helper speaks the Web `Response` API directly — no SDK, no imports. It runs
unchanged on **Cloudflare Workers**, **Node (>=18)**, and **Bun**, with no
dependencies and zero cold-start cost. This matches the [observability
standard](../observability/README.md) principle: *no SDK on the edge*.

## Wiring a worker

```ts
import { waveHealth } from "./health";

export default {
  fetch(req: Request, env: { WAVE_VERSION?: string }): Response {
    const url = new URL(req.url);
    if (url.pathname === "/health") {
      // service = this repo's slug, layer = its protocol-plane layer
      return waveHealth("wave-dispatch", "edge", env.WAVE_VERSION);
    }
    // ... rest of the worker
    return new Response("not found", { status: 404 });
  },
};
```

Need the raw object (e.g. to embed inside a richer `/status` payload)? Use
`waveHealthObject(service, layer, version)` and serialize it yourself.

## Migrating an existing worker

1. Drop `health.ts` into the worker (or import from the consumed foundation).
2. Replace the hand-rolled `/health` branch with a single `return waveHealth(...)`.
3. Pass the repo slug as `service` and the worker's layer as `layer`.
4. Wire `version` to your build var (git SHA / foundation pin) — leave it off to
   get `"unknown"` until the pipeline is ready.
