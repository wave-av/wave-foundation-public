// edge-proxy reference — request routing + CORS helpers.
//
// A thin edge surface owns a handful of public/infra routes and reverse-proxies the rest of /api/* to
// the origin. It performs NO auth — the gateway (the upstream auth/entitlement plane) enforces
// auth/scope/entitlement/meter in front of (or alongside) the origin. The surface only attaches product
// + protocol identity headers so the gateway/origin can attribute the call.

/** A parsed inbound request: method + normalized pathname + the leading path segment. */
export interface ParsedRoute {
  method: string;
  /** Pathname with any trailing slash stripped (except root "/"). */
  path: string;
  /** First non-empty path segment (e.g. "api" for "/api/v1/streams"), or "" for root. */
  head: string;
  /** Full URL object (query preserved). */
  url: URL;
}

/** Parse a Request into a normalized ParsedRoute. Pure, no side effects. */
export function parseRoute(req: Request): ParsedRoute {
  const url = new URL(req.url);
  let path = url.pathname;
  if (path.length > 1 && path.endsWith("/")) path = path.replace(/\/+$/, "");
  const head = path.split("/").filter(Boolean)[0] ?? "";
  return { method: req.method.toUpperCase(), path, head, url };
}

// ── CORS ──────────────────────────────────────────────────────────────────────
// A surface is called by browsers (web SDK) and agents. CORS is permissive on the WAVE-owned API surface
// but reflects only an allow-listed origin set when one is configured (SPOKE_CORS_ORIGINS, comma-sep).
// Default "*" is safe here because the surface carries NO cookies/credentials — auth is a Bearer header
// the caller sends explicitly, enforced downstream by the gateway.

const DEFAULT_ALLOW_HEADERS = "authorization, content-type, x-wave-product, x-wave-protocol, x-payment, payment";
const DEFAULT_ALLOW_METHODS = "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS";

/** Resolve the Access-Control-Allow-Origin value for this request given the configured allow-list. */
function resolveAllowOrigin(req: Request, configured?: string): string {
  if (!configured || configured.trim() === "" || configured.trim() === "*") return "*";
  const allow = configured.split(",").map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.get("origin") || "";
  return allow.includes(origin) ? origin : allow[0];
}

/** CORS headers for an actual (non-preflight) response. */
export function corsHeaders(req: Request, configured?: string): Record<string, string> {
  const allowOrigin = resolveAllowOrigin(req, configured);
  const h: Record<string, string> = {
    "access-control-allow-origin": allowOrigin,
    "access-control-expose-headers": "x-wave-product, x-wave-protocol, x-wave-spoke",
  };
  if (allowOrigin !== "*") h["vary"] = "Origin";
  return h;
}

/** Build a 204 preflight response. Returns null if the request is not an OPTIONS preflight. */
export function preflight(req: Request, configured?: string): Response | null {
  if (req.method.toUpperCase() !== "OPTIONS") return null;
  const allowOrigin = resolveAllowOrigin(req, configured);
  const reqHeaders = req.headers.get("access-control-request-headers");
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": allowOrigin,
      "access-control-allow-methods": DEFAULT_ALLOW_METHODS,
      "access-control-allow-headers": reqHeaders || DEFAULT_ALLOW_HEADERS,
      "access-control-max-age": "86400",
      ...(allowOrigin !== "*" ? { vary: "Origin" } : {}),
    },
  });
}
