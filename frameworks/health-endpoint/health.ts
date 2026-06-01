// WAVE health-endpoint helper — one /health JSON shape for every edge worker.
//
// Zero dependencies: speaks the Web `Response` API directly, so it runs unchanged
// on Cloudflare Workers, Node (>=18), and Bun with no SDK and no cold-start cost.
//
// Provenance: the `{ ok, service, layer, version }` shape was hand-rolled
// independently across all 7 edge workers (bridge / realtime / omt / dante /
// ndi / moq / dispatch). This is the one source of truth they consume instead.
//
// Standard: see ./README.md

/** The canonical WAVE health payload. Stable contract — monitors parse this. */
export interface WaveHealth {
  /** Always `true` when the worker is serving. Liveness, not deep readiness. */
  ok: true;
  /** Repo slug of the worker reporting, e.g. `"wave-dispatch"`. */
  service: string;
  /** Protocol-plane layer this worker sits on, e.g. `"edge"`. */
  layer: string;
  /** Build / foundation pin. `"unknown"` when not wired to a build var. */
  version: string;
}

/**
 * Build the canonical WAVE health JSON object.
 *
 * Pure + side-effect-free, so it is trivial to unit-test and to embed inside a
 * larger `/status` payload. Use {@link waveHealth} when you want a ready-to-return
 * `Response` on a worker's `/health` route.
 *
 * @param service repo slug of the reporting worker (e.g. `"wave-dispatch"`)
 * @param layer   protocol-plane layer (e.g. `"edge"`, `"bridges"`, `"local"`)
 * @param version build/foundation pin; defaults to `"unknown"`
 */
export function waveHealthObject(
  service: string,
  layer: string,
  version?: string,
): WaveHealth {
  return { ok: true, service, layer, version: version ?? "unknown" };
}

/**
 * Build a ready-to-return `/health` `Response` carrying the canonical WAVE
 * health JSON. Wire it directly into a worker's fetch handler:
 *
 * ```ts
 * if (url.pathname === "/health") {
 *   return waveHealth("wave-dispatch", "edge", env.WAVE_VERSION);
 * }
 * ```
 *
 * @param service repo slug of the reporting worker (e.g. `"wave-dispatch"`)
 * @param layer   protocol-plane layer (e.g. `"edge"`, `"bridges"`, `"local"`)
 * @param version build/foundation pin; defaults to `"unknown"`
 */
export function waveHealth(
  service: string,
  layer: string,
  version?: string,
): Response {
  return new Response(JSON.stringify(waveHealthObject(service, layer, version)), {
    headers: { "content-type": "application/json" },
  });
}
