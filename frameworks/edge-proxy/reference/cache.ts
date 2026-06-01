// edge-proxy reference — optional KV edge cache for idempotent GET proxies.
//
// A surface MAY cache safe, non-personalized GET responses from the origin at the edge to cut origin load
// and latency. This is OFF unless a CACHE KV namespace is bound AND the route opts in. It NEVER caches:
//   - non-GET/HEAD requests
//   - any request carrying an Authorization / X-Payment header (per-caller / billable → never shared)
//   - responses the origin marked private/no-store
// so a cache hit can never leak one caller's authorized data to another. Auth stays the gateway's job;
// caching here is purely a public-content optimization.

export interface CacheEnv {
  /** Optional KV namespace for the edge response cache. Unset ⇒ caching disabled (pass-through). */
  CACHE?: KVNamespace;
  /** Default cache TTL in seconds for opted-in routes (string env var). Default 60. */
  SPOKE_CACHE_TTL?: string;
  [k: string]: unknown;
}

/** Shape stored in KV: enough to faithfully reconstruct a cached Response. */
interface CachedEntry {
  status: number;
  headers: Record<string, string>;
  /** base64-encoded body (KV values are strings; binary-safe). */
  body: string;
}

/** True if this request is safe to even consider caching (idempotent + no per-caller auth/payment). */
export function isCacheable(req: Request): boolean {
  const m = req.method.toUpperCase();
  if (m !== "GET" && m !== "HEAD") return false;
  if (req.headers.get("authorization")) return false;
  if (req.headers.get("x-payment") || req.headers.get("payment")) return false;
  return true;
}

function cacheKey(req: Request): string {
  const u = new URL(req.url);
  return `cache:${u.pathname}${u.search}`;
}

/** Read a cached Response for this request, or null on miss/disabled/error (fail-open to origin). */
export async function readCache(env: CacheEnv, req: Request): Promise<Response | null> {
  if (!env.CACHE || !isCacheable(req)) return null;
  try {
    const entry = (await env.CACHE.get(cacheKey(req), { type: "json" })) as CachedEntry | null;
    if (!entry) return null;
    const body = Uint8Array.from(atob(entry.body), (c) => c.charCodeAt(0));
    return new Response(body, {
      status: entry.status,
      headers: { ...entry.headers, "x-wave-spoke-cache": "hit" },
    });
  } catch {
    return null; // fail-open: a cache error must never block the origin fetch
  }
}

function originAllowsCache(res: Response): boolean {
  const cc = (res.headers.get("cache-control") || "").toLowerCase();
  if (cc.includes("no-store") || cc.includes("private") || cc.includes("no-cache")) return false;
  if (res.headers.get("set-cookie")) return false;
  return res.status === 200;
}

/**
 * Conditionally store an origin Response in KV. Returns a (possibly tagged) Response to return to the
 * caller — the body is consumed here, so callers must use the returned clone. No-ops (returns the input
 * unchanged) when caching is disabled or the request/response is not cacheable.
 */
export async function writeCache(env: CacheEnv, req: Request, res: Response): Promise<Response> {
  if (!env.CACHE || !isCacheable(req) || !originAllowsCache(res)) return res;
  const buf = await res.clone().arrayBuffer();
  const headers: Record<string, string> = {};
  res.headers.forEach((v, k) => {
    if (k.toLowerCase() !== "set-cookie") headers[k] = v;
  });
  const entry: CachedEntry = {
    status: res.status,
    headers,
    body: btoa(String.fromCharCode(...new Uint8Array(buf))),
  };
  const ttl = Math.max(1, parseInt(env.SPOKE_CACHE_TTL || "60", 10) || 60);
  try {
    await env.CACHE.put(cacheKey(req), JSON.stringify(entry), { expirationTtl: ttl });
  } catch {
    // fail-open: failing to cache must never fail the response
  }
  return new Response(buf, { status: res.status, headers: { ...headers, "x-wave-spoke-cache": "miss" } });
}
