# Thin-Proxy Edge Chassis

Every WAVE edge surface — the spoke template, the marketing apex, the developer
portal — runs the **same** four-file reverse-proxy chassis in front of the
gateway/origin. The files are byte-for-byte identical across the fleet: the spoke
does **no** auth, scope-check, rate-limit, metering, or settlement; it forwards the
request, attaches attribution, and (optionally) caches public GETs. This framework
promotes that proven chassis as a standard plus a copyable conformance test, so a
new surface adopts it without re-deriving it (and the fleet stops drifting on
hand-rolled local copies).

> The gateway (Sub-Project A) is the only place auth/scope/entitlement/meter lives.
> If a spoke ever needs auth logic in its proxy, that is a design error — push it to
> the gateway. The chassis here is deliberately dumb.

## What the chassis guarantees

A surface that adopts this chassis (and passes the conformance suite) provides four
contracts:

1. **Fail-closed on misconfiguration.** If the origin is unconfigured, the proxy
   returns `502 ORIGIN_UNCONFIGURED` — never a fabricated `200`, never a silently
   dropped authorized request. A misconfigured edge fails loud, not quiet.

2. **Credentials pass through untouched.** The `Authorization` header reaches the
   origin **byte-identical**. The spoke never reads, mints, rewrites, or strips a
   credential. Auth is enforced downstream.

3. **Attribution is server-set, not client-claimed.** The spoke **overwrites** the
   `X-Wave-Product` / `X-Wave-Protocol` / `X-Wave-Spoke` headers with its own
   configured identity, so a caller cannot spoof a different product's SKU. These are
   the billing/observability attribution headers — they must be trustworthy.

4. **The edge cache can never leak per-caller data.** The optional KV cache stores
   **only** idempotent, unauthenticated, origin-approved GET/HEAD responses. Any
   request carrying `Authorization` / `X-Payment`, any non-GET, or any
   `private`/`no-store`/`Set-Cookie` response is never written — so a cache hit can
   never serve one caller's authorized data to another. Caching is a pure
   public-content optimization; auth stays the gateway's job.

## The four files

| File | Role |
|------|------|
| [`reference/proxy.ts`](reference/proxy.ts) | Reverse-proxy to the origin: fail-closed 502, attribution headers, `Authorization` pass-through, method/path/query/body preservation. |
| [`reference/route.ts`](reference/route.ts) | Pure request parsing + CORS helpers (preflight + actual-response headers). No side effects. |
| [`reference/cache.ts`](reference/cache.ts) | Optional, fail-open KV edge cache for idempotent public GETs. Off unless a `CACHE` namespace is bound. |
| [`reference/invariants.spec.ts`](reference/invariants.spec.ts) | The conformance suite — five executable invariants. Copy it into a spoke's `test/` to prove the chassis is intact. |

Placeholders in the reference files (genericized from the proven fleet copies):

- `__ORIGIN_URL__` — env var naming the origin to proxy `/api/*` to (e.g.
  `https://api.example.com`). Fail-closed 502 if unset.
- `__PRODUCT__` — the surface's product/SKU label, sent as `X-Wave-Product`.
- `__PROTOCOL__` — optional protocol label (`srt|rtmp|webrtc|http|…`), sent as
  `X-Wave-Protocol`.
- `__SPOKE_NAME__` — the surface's deploy name, sent as `X-Wave-Spoke`.

The header names (`x-wave-*`) and the `502 ORIGIN_UNCONFIGURED` error shape are part
of the contract — keep them stable so the gateway/origin attribution and the
conformance suite both line up.

## The five conformance invariants

The suite ([`reference/invariants.spec.ts`](reference/invariants.spec.ts)) runs inside
the real `workerd` runtime (`@cloudflare/vitest-pool-workers`), stubs the **global**
`fetch` so the spoke never hits the network, and asserts the exact `Request` the spoke
sends to the origin. The five invariants:

| # | Invariant | What it proves |
|---|-----------|----------------|
| **(a)** | `Authorization` reaches the origin byte-identical | The spoke never reads/mints/strips the credential (guarantee 2). |
| **(b)** | A client-sent `X-Wave-Product` is overwritten by the configured product | No attribution spoofing (guarantee 3). |
| **(c)** | A GET carrying `Authorization` is never written to the cache KV | No cross-caller leak; paired with a positive control proving public GETs *do* cache (guarantee 4). |
| **(d)** | Unset origin fails closed → `502 ORIGIN_UNCONFIGURED`, with no origin fetch attempted | Fail-closed, never a fabricated 200 (guarantee 1). |
| **(e)** | `/api/*` misses still proxy; an unknown non-`/api` path 404s without touching the origin | The surface owns only its own route surface — no silent open proxy. |

Drop any one and the chassis stops being trustworthy: skip (a)/(b) and attribution
lies; skip (c) and the cache leaks; skip (d) and a misconfig serves fake successes;
skip (e) and the edge becomes an open relay.

## How a surface adopts it

1. Copy the three runtime files into the surface's `src/` and replace the four
   placeholders with the surface's real env-var names / SKU / protocol / deploy name
   (typically via `wrangler.toml` `[vars]` + KV binding, not hard-coded).
2. Wire them into the Worker `fetch` handler: `parseRoute` → `preflight` (OPTIONS) →
   `readCache` (GET hit) → `proxyToOrigin` → `writeCache`; 404 any unknown non-`/api`
   path with the `NOT_FOUND` shape.
3. Copy [`reference/invariants.spec.ts`](reference/invariants.spec.ts) into the
   surface's `test/`, point its `worker` import at the surface entry, and run it under
   `@cloudflare/vitest-pool-workers`. All five invariants must pass before deploy.
4. Keep the copies byte-identical to this reference (modulo the placeholder
   substitution) — divergence is the drift this framework exists to kill. A CI hash
   check against this reference is the cheap way to enforce that.

## Anti-patterns

- ❌ Adding auth/scope/rate-limit/metering to the proxy. That belongs in the gateway.
- ❌ Reading or rewriting `Authorization` (breaks invariant (a) and silently changes
  who the origin thinks is calling).
- ❌ Trusting a client-supplied `X-Wave-Product`/`X-Wave-Protocol` (breaks (b);
  attribution and billing then run on a spoofable value).
- ❌ Caching authenticated or `x-payment`-bearing requests "for speed" (breaks (c);
  this is the cross-caller leak the cache contract forbids).
- ❌ Returning a fabricated `200`/empty body when the origin is unset (breaks (d);
  fail closed with the 502).
- ❌ Falling back to a blanket proxy for unknown paths (breaks (e); a surface owns
  only its declared routes).
- ❌ Letting the per-spoke copies drift from this reference — that copy-paste drift is
  exactly what promoting the chassis here eliminates.

## Provenance

Harvested from the proven edge fleet, where all four files are byte-identical:

- `proxy.ts` / `route.ts` / `cache.ts` — `src/`
- `invariants.spec.ts` — `test/`

Proven across the spoke template, the marketing apex surface, and the developer
portal (3 surfaces, identical SHA-256 per file at harvest time). The files were
genericized here — WAVE-internal SKU/origin/protocol names replaced with the
`__PLACEHOLDER__` form above — but the logic, header contract, and error shapes are
unchanged from the deployed copies.

## Relation to other frameworks

- [`harvest`](../harvest/) — how this chassis was promoted from the sibling spokes
  (proven in 3 surfaces, cross-product, a pattern not an instance, stable).
- [`gates`](../gates/) — the conformance suite is the per-surface gate; a fleet-level
  hash check (this reference vs each spoke's copy) is the anti-drift gate.
- [`build-on-wave`](../build-on-wave/) — every customer-buildable surface starts from
  this same thin-proxy chassis; "what we built, you can build."
- [`observability`](../observability/) — the `X-Wave-Spoke`/`X-Wave-Product` headers
  this chassis stamps are the attribution dimensions observability slices on.
