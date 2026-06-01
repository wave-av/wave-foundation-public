// edge-proxy reference — reverse-proxy to the origin.
//
// THE CORE OF A THIN EDGE SURFACE. A surface does NOT authenticate, scope-check, rate-limit, meter, or
// settle payments — the gateway (the upstream auth/entitlement plane) does all of that in front of /
// alongside the origin. The surface's only proxy responsibilities are:
//   1. forward the inbound Authorization header UNTOUCHED (the gateway/origin enforce it),
//   2. attach X-Wave-Product + X-Wave-Protocol so the call is attributed to this surface's SKU/protocol,
//   3. stamp X-Wave-Spoke (the surface name) for observability,
//   4. preserve method, path, query, and body; stream the response back.
//
// If a surface ever needs to add auth logic here, that is a design error — push it to the gateway.
//
// Placeholders to substitute when adopting (see frameworks/edge-proxy/README.md):
//   __ORIGIN_URL__  — env var naming the origin to proxy /api/* to (fail-closed 502 if unset)
//   __PRODUCT__     — this surface's product/SKU label (sent as X-Wave-Product)
//   __PROTOCOL__    — optional protocol label (sent as X-Wave-Protocol)
//   __SPOKE_NAME__  — this surface's deploy name (sent as X-Wave-Spoke)

export interface ProxyEnv {
  /** Origin to proxy /api/* to. Required (fail-closed 502 if unset). Default in wrangler.toml [vars]. */
  ORIGIN_URL?: string;
  /** This surface's product/SKU label. Sent as X-Wave-Product. REQUIRED per surface. */
  WAVE_PRODUCT?: string;
  /** This surface's protocol label (e.g. srt|rtmp|webrtc|http). Sent as X-Wave-Protocol. */
  WAVE_PROTOCOL?: string;
  /** This surface's deploy name, for X-Wave-Spoke. Defaults to "spoke". */
  WAVE_SPOKE_NAME?: string;
  [k: string]: unknown;
}

function json(body: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...extra },
  });
}

/**
 * Reverse-proxy `req` to `ORIGIN_URL`, preserving path+query+body+method.
 *
 * - FAIL-CLOSED if ORIGIN_URL is unset: we return 502 rather than silently 200 or drop an authorized
 *   request (mirrors the gateway's forward() discipline).
 * - Authorization is PASSED THROUGH verbatim — the surface never reads, mints, or strips credentials.
 * - X-Wave-Product / X-Wave-Protocol / X-Wave-Spoke are attached for attribution (overwriting any
 *   client-supplied values so a caller cannot spoof a different product's identity).
 */
export async function proxyToOrigin(
  req: Request,
  env: ProxyEnv,
  extraHeaders: Record<string, string> = {},
): Promise<Response> {
  if (!env.ORIGIN_URL) {
    return json({ error: { code: "ORIGIN_UNCONFIGURED", message: "surface origin not configured" } }, 502);
  }
  const inUrl = new URL(req.url);
  const target = new URL(env.ORIGIN_URL.replace(/\/+$/, "") + inUrl.pathname + inUrl.search);

  // Clone inbound headers, then OVERWRITE the WAVE attribution headers (clients cannot spoof them).
  const headers = new Headers(req.headers);
  headers.set("x-wave-product", env.WAVE_PRODUCT || "unknown");
  if (env.WAVE_PROTOCOL) headers.set("x-wave-protocol", env.WAVE_PROTOCOL);
  else headers.delete("x-wave-protocol");
  headers.set("x-wave-spoke", env.WAVE_SPOKE_NAME || "spoke");
  for (const [k, v] of Object.entries(extraHeaders)) headers.set(k, v);
  // Authorization is intentionally NOT touched — it rides through exactly as the caller sent it.
  headers.set("host", target.host);

  const proxied = new Request(target.toString(), {
    method: req.method,
    headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : req.body,
    redirect: "manual",
  });
  return fetch(proxied);
}
