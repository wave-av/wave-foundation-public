// @wave-av/verify-loop — the WAVE fractal verify primitive.
//
// ONE loop, every scale: discover → run the real path → emit {verdict, provenance}
// → refuse to advance on red → make the red visible. The same shape verifies an
// example (a doc code block), a doc (followed cold), a surface (wave-bench grade),
// the fleet (conformance), and the platform (attestation). Build it ONCE here;
// instantiate it everywhere. (NORTHSTAR §1; docs/docs-dogfood/NORTHSTAR.md.)
//
// SSoT = wave-foundation/frameworks/verify-loop/verify-loop.mjs. Consumers VENDOR a
// byte-identical copy (e.g. scripts/lib/verify-loop.mjs) guarded by a *-ssot-drift
// CI check — the same pattern as frameworks/bench. Never fork it.
//
// Pure ESM, Node stdlib only (global fetch + AbortController). No deps, no shell,
// no secrets. SSRF-safe by construction: every outbound request is GET-only,
// http/https-only, credential-free, redirect-not-followed, and time-bounded.

export const VERIFY_LOOP_VERSION = "1.0.0";

// ─────────────────────────────────────────────────────────────────────────────
// Existence semantics — the doc-tests.mjs verdict, generalized.
//
// A documented URL "exists" if it answers in a way that proves the route is real:
//   • 2xx / 3xx              → exists (a redirect is a live route, not a dead one)
//   • 401 / 402 / 403        → exists (an auth- or payment-gated route is HEALTHY,
//                              not broken — a documented paid endpoint SHOULD 402)
//   • 404 / 410 / 5xx / none → fail
export function existsByStatus(status) {
  if (typeof status !== "number" || !Number.isFinite(status)) return false;
  if (status >= 200 && status < 400) return true;
  if (status === 401 || status === 402 || status === 403) return true;
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// SSRF-safe existence probe.
//
// GET only · http/https only · NO credentials in the URL · redirect:"manual" (a
// 3xx is recorded as proof-of-life but NOT chased, so a redirect can't tunnel into
// a private network) · hard timeout. Returns {status|null, ok, error?}.
//
// This enforces method/protocol/credential/redirect/timeout. For probing fully
// UNTRUSTED URLs, additionally layer a private-IP blocker (e.g. ssrf-req-filter) by
// passing a guarded `fetchImpl`; WAVE doc/surface URLs are first-party so the
// no-chase + protocol guard is the relevant defense.
const ALLOWED_PROTOCOLS = new Set(["http:", "https:"]);

export async function probe(url, { timeoutMs = 8000, fetchImpl = globalThis.fetch } = {}) {
  let u;
  try {
    u = new URL(url);
  } catch {
    return { status: null, ok: false, error: "invalid-url" };
  }
  if (!ALLOWED_PROTOCOLS.has(u.protocol)) {
    return { status: null, ok: false, error: `bad-protocol:${u.protocol}` };
  }
  if (u.username || u.password) {
    return { status: null, ok: false, error: "credentials-in-url" };
  }
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const res = await fetchImpl(u.href, { method: "GET", redirect: "manual", signal: ac.signal });
    return { status: res.status, ok: existsByStatus(res.status) };
  } catch (e) {
    return { status: null, ok: false, error: e && e.name === "AbortError" ? "timeout" : "unreachable" };
  } finally {
    clearTimeout(timer);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bounded-concurrency map (no deps). Preserves input order; never more than
// `limit` calls to `fn` in flight at once.
export async function mapLimit(items, limit, fn) {
  const arr = Array.from(items);
  const out = new Array(arr.length);
  const n = Math.max(1, Math.min(Math.floor(limit) || 1, arr.length || 1));
  let next = 0;
  async function worker() {
    while (next < arr.length) {
      const idx = next++;
      out[idx] = await fn(arr[idx], idx);
    }
  }
  await Promise.all(Array.from({ length: n }, worker));
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Verdict — fold checks ({name, ok, detail?}) into a refuse-on-red decision.
export function verdict(checks) {
  const list = Array.isArray(checks) ? checks : [];
  const red = list.filter((c) => !c || !c.ok);
  return {
    ok: red.length === 0,
    total: list.length,
    pass: list.length - red.length,
    fail: red.length,
    red: red.map((c) => ({ name: (c && c.name) || "?", detail: (c && c.detail) ?? null })),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Secret scrubbing — provenance must be auditable AND must never leak a key.
//
// Drops secret-ish object keys, redacts secret-ish query params + URL credentials,
// and masks long opaque token-like strings. Defense-in-depth so a caller who
// accidentally threads a test API key into `inputs`/`extra` cannot publish it.
const SECRET_KEY_RE =
  /(api[_-]?key|secret|token|password|passwd|authorization|bearer|cookie|credential|private[_-]?key)/i;

function looksLikeOpaqueSecret(s) {
  // long, no whitespace/slashes/colons, mixes letters+digits → token-shaped.
  return /^[A-Za-z0-9_\-.]{24,}$/.test(s) && /[0-9]/.test(s) && /[A-Za-z]/.test(s);
}

function scrubUrlString(s) {
  try {
    const u = new URL(s);
    let changed = false;
    for (const k of [...u.searchParams.keys()]) {
      if (SECRET_KEY_RE.test(k)) {
        u.searchParams.set(k, "[redacted]");
        changed = true;
      }
    }
    if (u.username || u.password) {
      u.username = "";
      u.password = "";
      changed = true;
    }
    return changed ? u.href : s;
  } catch {
    return s;
  }
}

export function scrubSecrets(value, depth = 0) {
  if (depth > 6) return "[depth-capped]";
  if (Array.isArray(value)) return value.map((v) => scrubSecrets(v, depth + 1));
  if (value && typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (SECRET_KEY_RE.test(k)) {
        out[k] = "[redacted]";
        continue;
      }
      out[k] = scrubSecrets(v, depth + 1);
    }
    return out;
  }
  if (typeof value === "string") {
    if (s_hasUrlShape(value)) {
      const scrubbed = scrubUrlString(value);
      return looksLikeOpaqueSecret(scrubbed) ? "[redacted]" : scrubbed;
    }
    return looksLikeOpaqueSecret(value) ? "[redacted]" : value;
  }
  return value;
}

function s_hasUrlShape(s) {
  return s.startsWith("http://") || s.startsWith("https://");
}

// ─────────────────────────────────────────────────────────────────────────────
// Provenance — a structured, SECRET-FREE run record (never fabricate it; derive
// it from the real run). Timestamps are passed IN by the caller (a real script
// supplies new Date().toISOString()) so the primitive itself stays pure/testable.
export function provenance({ tool, startedAt = null, finishedAt = null, inputs = {}, extra = {} } = {}) {
  return {
    tool: String(tool || "verify-loop"),
    verify_loop: VERIFY_LOOP_VERSION,
    startedAt,
    finishedAt,
    inputs: scrubSecrets(inputs),
    ...scrubSecrets(extra),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// runChecks — the loop in one call: probe every target (bounded), build the
// verdict, attach scrubbed provenance. The reusable "run the real path → emit
// verdict+provenance" used by doc-tests, autogen link-checks, changelog, etc.
export async function runChecks(targets, opts = {}) {
  const {
    tool = "verify-loop",
    concurrency = 8,
    timeoutMs = 8000,
    fetchImpl = globalThis.fetch,
    startedAt = null,
    finishedAt = null,
  } = opts;
  const list = Array.from(targets);
  const results = await mapLimit(list, concurrency, async (t) => {
    const p = await probe(t.url, { timeoutMs, fetchImpl });
    return {
      name: t.name || t.url,
      url: t.url,
      status: p.status,
      ok: p.ok,
      detail: p.ok ? `status=${p.status}` : p.error || `status=${p.status}`,
    };
  });
  return {
    verdict: verdict(results),
    provenance: provenance({
      tool,
      startedAt,
      finishedAt,
      inputs: { count: list.length, concurrency, timeoutMs },
      extra: { checks: results },
    }),
    results,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Hermetic self-test — "a gate that can only PASS is worse than none." This MUST
// include known-BAD inputs that the loop is required to REJECT, so a regression
// that makes everything pass fails loudly here. Pure (no network: probe is tested
// with an injected fetchImpl). Returns {ok, results:[{name, ok, detail}]}.
export async function selfTest() {
  const results = [];
  const expect = (name, cond, detail = "") => results.push({ name, ok: !!cond, detail });

  // existsByStatus — both directions, incl. the must-FAIL cases.
  for (const [status, want] of [
    [200, true], [204, true], [301, true], [302, true], [308, true],
    [401, true], [402, true], [403, true],
    [404, false], [410, false], [418, false], [429, false], [500, false], [503, false],
    [null, false], ["200", false], [NaN, false],
  ]) {
    expect(`existsByStatus(${String(status)})==${want}`, existsByStatus(status) === want);
  }

  // verdict — empty is ok; one red flips it; counts + red names correct.
  const v0 = verdict([]);
  expect("verdict([]) ok", v0.ok && v0.total === 0);
  const v1 = verdict([{ name: "a", ok: true }, { name: "b", ok: false, detail: "404" }]);
  expect("verdict one-red not ok", v1.ok === false && v1.fail === 1 && v1.pass === 1);
  expect("verdict red carries name+detail", v1.red[0].name === "b" && v1.red[0].detail === "404");

  // mapLimit — runs all, preserves order, never exceeds the limit.
  let inFlight = 0;
  let maxInFlight = 0;
  const mapped = await mapLimit([1, 2, 3, 4, 5, 6, 7], 3, async (x) => {
    inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
    await new Promise((r) => setTimeout(r, 5));
    inFlight--;
    return x * 2;
  });
  expect("mapLimit order+values", JSON.stringify(mapped) === JSON.stringify([2, 4, 6, 8, 10, 12, 14]));
  expect(`mapLimit concurrency<=3 (saw ${maxInFlight})`, maxInFlight <= 3 && maxInFlight >= 1);

  // scrubSecrets — redacts keys, url query secrets, url creds, opaque tokens;
  // spares normal slugs and clean URLs.
  const scrubbed = scrubSecrets({
    apiKey: "sk-abc123def456", // gitleaks:allow — fixture; the next expect() asserts it gets redacted
    nested: { Authorization: "Bearer xyz" },
    slug: "agent-commerce",
    clean: "https://docs.wave.online/docs/mcp",
    // NB: a non-secret-ish key name on purpose, so the URL-query path runs (a key
    // like "token"/"apiKey" would be redacted whole at the object level first).
    endpoint: "https://api.wave.online/v1/x?api_key=supersecretvalue123",
  });
  expect("scrub object secret key", scrubbed.apiKey === "[redacted]");
  expect("scrub nested secret key", scrubbed.nested.Authorization === "[redacted]");
  expect("scrub spares slug", scrubbed.slug === "agent-commerce");
  expect("scrub spares clean url", scrubbed.clean === "https://docs.wave.online/docs/mcp");
  expect("scrub url query secret", /api_key=%5Bredacted%5D/.test(scrubbed.endpoint));
  expect("scrub keeps url path intact", scrubbed.endpoint.startsWith("https://api.wave.online/v1/x?"));

  // probe — injected fetchImpl, no network. exercises each guard.
  const ok200 = await probe("https://x.test/a", { fetchImpl: async () => ({ status: 200 }) });
  expect("probe 200 ok", ok200.ok === true && ok200.status === 200);
  const r301 = await probe("https://x.test/r", { fetchImpl: async () => ({ status: 301 }) });
  expect("probe 301 exists (not chased)", r301.ok === true && r301.status === 301);
  const r404 = await probe("https://x.test/missing", { fetchImpl: async () => ({ status: 404 }) });
  expect("probe 404 fails", r404.ok === false);
  const ftp = await probe("ftp://x.test/a", { fetchImpl: async () => ({ status: 200 }) });
  expect("probe rejects non-http proto", ftp.ok === false && /bad-protocol/.test(ftp.error));
  const creds = await probe("https://u:p@x.test/a", { fetchImpl: async () => ({ status: 200 }) });
  expect("probe rejects url creds", creds.ok === false && creds.error === "credentials-in-url");
  const bad = await probe("not a url", { fetchImpl: async () => ({ status: 200 }) });
  expect("probe rejects invalid url", bad.ok === false && bad.error === "invalid-url");
  const timeout = await probe("https://x.test/slow", {
    fetchImpl: async () => { const e = new Error("abort"); e.name = "AbortError"; throw e; },
  });
  expect("probe maps abort→timeout", timeout.ok === false && timeout.error === "timeout");

  // provenance — never leaks a secret threaded through inputs/extra.
  const prov = provenance({ tool: "t", inputs: { token: "leakme123456789012345" }, extra: { note: "ok" } }); // gitleaks:allow — fixture; the next expect() asserts it gets redacted
  expect("provenance redacts secret input", prov.inputs.token === "[redacted]");
  expect("provenance keeps tool + version", prov.tool === "t" && prov.verify_loop === VERIFY_LOOP_VERSION);

  return { ok: results.every((r) => r.ok), results };
}

// CLI: `node verify-loop.mjs` runs the hermetic self-test and exits non-zero on
// any failure. Zero-dependency, runnable anywhere.
if (import.meta.url === `file://${process.argv[1]}`) {
  selfTest().then(({ ok, results }) => {
    for (const r of results) {
      if (!r.ok) console.error(`  ✗ ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
    }
    const pass = results.filter((r) => r.ok).length;
    console.log(`${ok ? "✓" : "✗"} verify-loop self-test: ${pass}/${results.length} checks (v${VERIFY_LOOP_VERSION})`);
    process.exit(ok ? 0 : 1);
  });
}
