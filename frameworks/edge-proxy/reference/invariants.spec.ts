// edge-proxy reference — executable edge-surface invariants (a copyable conformance suite).
//
// COPY THIS INTO A SURFACE'S `test/`, point the `worker` import at the surface entry, and run it under
// @cloudflare/vitest-pool-workers. It calls the Worker's fetch handler directly with the deployed env
// (from wrangler.toml) and stubs the GLOBAL `fetch` so we can capture the EXACT Request the surface
// sends to the origin and assert on it — the surface must never reach the real network in a unit test.
//
// The five invariants asserted (see frameworks/edge-proxy/README.md §"The five conformance invariants"):
//   (a) Authorization reaches the origin byte-identical (the surface never reads/mints/strips it).
//   (b) A client-sent X-Wave-Product is OVERWRITTEN by env.WAVE_PRODUCT (no attribution spoofing).
//   (c) A GET carrying Authorization is NEVER written to the CACHE KV (no cross-caller leak).
//   (d) Unset ORIGIN_URL fails closed → 502 ORIGIN_UNCONFIGURED (never a fabricated 200).
//   (e) /api/* misses still proxy; a non-/api unknown path 404s (the surface owns only its surface).

import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/worker";

const ORIGIN = "https://api.example.com";

// The surface's Env carries an index signature (ProxyEnv/CacheEnv allow extra keys), so the
// `cloudflare:test` `env` (typed Cloudflare.Env) needs a cast to the worker's Env at the boundary.
type SpokeEnv = Parameters<typeof worker.fetch>[1];
const spokeEnv = env as unknown as SpokeEnv;

// CACHE is optional on the Env type (caching is opt-in) but the vitest config always binds it, so
// every test can rely on a real KV namespace here.
const cache = spokeEnv.CACHE as KVNamespace;

// Drive the Worker exactly as the runtime would. The surface's fetch handler takes (req, env) and
// does all its work inline (no ctx.waitUntil), so no ExecutionContext plumbing is needed.
async function call(req: Request, overrides: Partial<SpokeEnv> = {}): Promise<Response> {
  return worker.fetch(req, { ...spokeEnv, ...overrides } as SpokeEnv);
}

// Stub global fetch so the surface's proxyToOrigin() reaches our spy instead of the network. The spy
// records the outbound Request (so we can assert headers/url) and returns a caller-supplied
// Response. Returns a getter for the captured Request.
function stubOrigin(make: (out: Request) => Response): { captured: () => Request } {
  let out: Request | undefined;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    out = input instanceof Request ? input : new Request(input as string | URL, init);
    return make(out);
  });
  return {
    captured: () => {
      if (!out) throw new Error("origin fetch was never called");
      return out;
    },
  };
}

beforeEach(async () => {
  // Each test starts from an empty cache so KV assertions are unambiguous.
  const keys = await cache.list();
  await Promise.all(keys.keys.map((k: { name: string }) => cache.delete(k.name)));
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("(a) Authorization reaches origin byte-identical", () => {
  it("forwards the exact Bearer token the caller sent, unmodified", async () => {
    const TOKEN = "Bearer wave_live_AbC123.dEf456-gHi_789=="; // pragma: allowlist secret
    const origin = stubOrigin(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));

    const res = await call(
      new Request(`${ORIGIN}/api/v1/streams`, {
        method: "POST",
        headers: { authorization: TOKEN, "content-type": "application/json" },
        body: JSON.stringify({ name: "x" }),
      }),
    );

    expect(res.status).toBe(200);
    expect(origin.captured().headers.get("authorization")).toBe(TOKEN); // byte-identical, not re-minted
  });
});

describe("(b) X-Wave-Product is server-set, overwriting any client value", () => {
  it("replaces a spoofed client X-Wave-Product with env.WAVE_PRODUCT", async () => {
    const origin = stubOrigin(
      () => new Response("{}", { status: 200, headers: { "cache-control": "no-store" } }),
    );

    const res = await call(
      new Request(`${ORIGIN}/api/v1/ping`, { headers: { "x-wave-product": "SOME_OTHER_SKU_I_DO_NOT_OWN" } }),
    );

    expect(res.status).toBe(200);
    const sent = origin.captured().headers.get("x-wave-product");
    expect(sent).toBe(spokeEnv.WAVE_PRODUCT); // the surface's own SKU, not the client's claim
    expect(sent).not.toBe("SOME_OTHER_SKU_I_DO_NOT_OWN");
  });
});

describe("(c) authenticated GETs are never written to the cache", () => {
  it("does NOT write a GET carrying Authorization into CACHE KV", async () => {
    // A cacheable-LOOKING origin response (200, public) — it must STILL not be cached, because the
    // request carried Authorization (per-caller data must never be shared at the edge).
    stubOrigin(
      () =>
        new Response(JSON.stringify({ user: "secret" }), {
          status: 200,
          headers: { "cache-control": "public, max-age=300" },
        }),
    );

    const res = await call(
      new Request(`${ORIGIN}/api/v1/me`, { headers: { authorization: "Bearer wave_live_secret" } }), // pragma: allowlist secret
    );
    expect(res.status).toBe(200);

    // Nothing per-caller may have landed in KV.
    const after = await cache.list();
    expect(after.keys).toHaveLength(0);
    expect(await cache.get("cache:/api/v1/me")).toBeNull();
  });

  it("DOES cache an unauthenticated, cacheable public GET (positive control)", async () => {
    stubOrigin(
      () =>
        new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "cache-control": "public, max-age=300" },
        }),
    );

    const res = await call(new Request(`${ORIGIN}/api/v1/public`));
    expect(res.status).toBe(200);
    expect(res.headers.get("x-wave-spoke-cache")).toBe("miss");

    // Confirms (c)'s negative result is meaningful (the cache path IS live for public GETs).
    expect(await cache.get("cache:/api/v1/public")).not.toBeNull();
  });
});

describe("(d) fail-closed on unconfigured origin", () => {
  it("returns 502 ORIGIN_UNCONFIGURED when ORIGIN_URL is unset (never a fake 200)", async () => {
    const spy = vi.spyOn(globalThis, "fetch");
    const res = await call(new Request(`${ORIGIN}/api/v1/anything`), { ORIGIN_URL: undefined });

    expect(res.status).toBe(502);
    const body = (await res.json()) as { error: { code: string } };
    expect(body.error.code).toBe("ORIGIN_UNCONFIGURED");
    expect(spy).not.toHaveBeenCalled(); // failed closed BEFORE any origin call
  });
});

describe("(e) routing surface: /api/* proxies, unknown non-/api 404s", () => {
  it("proxies an /api/* cache MISS through to the origin", async () => {
    // Origin's 404 (not the surface's) proves the request was proxied, not short-circuited.
    const origin = stubOrigin(
      () =>
        new Response(JSON.stringify({ error: "origin says no" }), {
          status: 404,
          headers: { "cache-control": "no-store" },
        }),
    );

    const res = await call(new Request(`${ORIGIN}/api/v1/unknown-but-proxied`));
    expect(res.status).toBe(404);
    expect(origin.captured().url).toBe(`${ORIGIN}/api/v1/unknown-but-proxied`);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("origin says no");
  });

  it("404s a non-/api unknown path without ever touching the origin", async () => {
    const spy = vi.spyOn(globalThis, "fetch");
    const res = await call(new Request(`${ORIGIN}/not-a-surface-route`));

    expect(res.status).toBe(404);
    const body = (await res.json()) as { error: { code: string } };
    expect(body.error.code).toBe("NOT_FOUND");
    expect(spy).not.toHaveBeenCalled(); // a surface owns only its surface — no silent proxy
  });
});
