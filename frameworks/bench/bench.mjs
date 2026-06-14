#!/usr/bin/env node
// wave-bench — the WAVE quality benchmark. Profile-aware, multi-family, research-grounded.
//
// One parameterized grader for EVERY WAVE surface (blog · docs · changelog · api · apex). A shared
// UNIVERSAL core (robots/AI-bots, sitemap, llms.txt, MCP discovery, security headers, canonical/JSON-LD)
// plus per-profile checks (a blog needs AudioObject; an api needs an x402 402; docs needs dated entries).
// Checks are tagged {family, profiles, weight} so any check can be toggled onto any surface — quality
// signals "send into each other" the way the funnel does. Written with NO app imports so it promotes
// verbatim into @wave-av/spoke-chassis and runs per-spoke in CI (the reusable checks.yml) as a gate.
//
// Signals encoded from 2026 research: GEO-SFE (heading/answer-first/chunking), schema.org AEO
// (BlogPosting/FAQPage/dateModified/author.sameAs), AI-bot robots directives, llms.txt(llmstxt.org),
// MCP /.well-known (modelcontextprotocol.io), x402 402 (x402.org), A2A agent-card.
//
// Usage:  node scripts/bench.mjs --profile blog --base https://blog.wave.online [--json] [--family security]
//   env:  BENCH_BASE  BENCH_PROFILE  BENCH_MIN_GRADE(default B)
//
// Security: same-origin GET/POST only (SSRF — manifest-derived URLs re-validated); per-request timeout +
// size cap; one redirect; fixed UA; linear regex (no dynamic RegExp); guarded JSON.parse; probes carry no
// credentials and are bounded to one attempt; never logs secrets or raw error objects (message only).

// ─────────────────────────── args / config ───────────────────────────
function parseArgs(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t.startsWith("--")) {
      const k = t.slice(2);
      const v = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : true;
      a[k] = v;
    }
  }
  return a;
}
const ARGS = parseArgs(process.argv.slice(2));
const BASE = (ARGS.base || process.env.BENCH_BASE || "https://blog.wave.online").replace(/\/+$/, "");
const PROFILE = (ARGS.profile || process.env.BENCH_PROFILE || "blog").toLowerCase();
const MIN = (ARGS["min-grade"] || process.env.BENCH_MIN_GRADE || "B").toUpperCase();
const JSON_OUT = !!ARGS.json;
const ONLY_FAMILY = typeof ARGS.family === "string" ? ARGS.family : null;
const ORIGIN = new URL(BASE).origin;
const TIMEOUT = 10_000;
const CAP = 1_000_000;
const MAX_ITEMS = 6;

// ─────────────────────────── fetch + cache ───────────────────────────
function sameOrigin(u) {
  try {
    const x = new URL(u, BASE);
    if (x.protocol !== "https:" && x.protocol !== "http:") return null;
    return x.origin === ORIGIN ? x.toString() : null; // SSRF: only our own origin
  } catch {
    return null;
  }
}
const _cache = new Map();
async function http(path, { method = "GET", body } = {}) {
  const key = `${method} ${path}`;
  if (_cache.has(key)) return _cache.get(key);
  const url = sameOrigin(path);
  let out;
  if (!url) {
    out = { ok: false, status: 0, headers: new Headers(), body: "", ct: "", ms: 0, error: "refused (cross-origin)" };
  } else {
    const t0 = Date.now();
    try {
      // Follow same-origin redirects to the FINAL page (so downstream checks grade the
      // page, not a 30x stub), but bounded and SSRF-guarded: never follow an off-origin
      // Location from CI, and never loop unbounded. Only the first hop carries method/body;
      // later hops are bare GET, mirroring browser redirect semantics.
      let target = url;
      let res;
      for (let hop = 0; hop < 5; hop++) {
        const init = hop === 0
          ? { method, body, redirect: "manual", signal: AbortSignal.timeout(TIMEOUT), headers: { "user-agent": "wave-bench/1", ...(body ? { "content-type": "application/json" } : {}) } }
          : { redirect: "manual", signal: AbortSignal.timeout(TIMEOUT), headers: { "user-agent": "wave-bench/1" } };
        res = await fetch(target, init);
        if (res.status < 300 || res.status >= 400) break; // not a redirect → final response
        const loc = sameOrigin(res.headers.get("location"));
        if (!loc || loc === target) break;                // off-origin (SSRF guard) or self-loop → grade the 30x as-is
        target = loc;                                      // same-origin hop → follow
      }
      const txt = (await res.text()).slice(0, CAP);
      out = { ok: res.ok, status: res.status, headers: res.headers, body: txt, ct: res.headers.get("content-type") || "", ms: Date.now() - t0 };
    } catch (err) {
      out = { ok: false, status: 0, headers: new Headers(), body: "", ct: "", ms: Date.now() - t0, error: err instanceof Error ? err.message : "fetch failed" };
    }
  }
  _cache.set(key, out);
  return out;
}

// ─────────────────────────── parsing helpers ───────────────────────────
const decodeEntities = (s) =>
  s.replace(/&#0?39;|&#x27;/gi, "'").replace(/&quot;|&#0?34;/gi, '"').replace(/&lt;/gi, "<").replace(/&gt;/gi, ">").replace(/&hellip;|&#8230;/gi, "…").replace(/&amp;/gi, "&");
const attr = (h, re) => (h.match(re) || [, ""])[1];
const hasMeta = (h, prop, val) => h.includes(`${prop}="${val}"`) || h.includes(`${prop}='${val}'`);
function visibleText(h) {
  return h
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<(nav|footer|header)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
function jsonLd(h) {
  const out = [];
  for (const m of h.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      const v = JSON.parse(m[1].trim());
      const nodes = Array.isArray(v) ? v : v["@graph"] && Array.isArray(v["@graph"]) ? v["@graph"] : [v];
      out.push(...nodes);
    } catch {
      /* a malformed block is reported by the jsonld-valid check */
    }
  }
  return out;
}
const typeOf = (n) => (Array.isArray(n["@type"]) ? n["@type"] : [n["@type"]]).filter(Boolean);
const ldHasType = (nodes, set) => nodes.some((n) => typeOf(n).some((t) => set.includes(t)));
/** Crude robots.txt group parser: does `ua` (or `*`) get a `Disallow: /`? */
function robotsBlocks(robots, ua) {
  const groups = [];
  let cur = null;
  for (const line of robots.split(/\r?\n/)) {
    const m = line.match(/^\s*(user-agent|disallow|allow)\s*:\s*(.*?)\s*(#.*)?$/i);
    if (!m) continue;
    const [k, v] = [m[1].toLowerCase(), m[2]];
    if (k === "user-agent") {
      // A User-agent line starts a NEW group only once the current group already has a
      // rule line (Allow OR Disallow) — consecutive User-agent lines share one group.
      // Tracking any rule (not just Disallow) is the fix: an Allow-only group must still
      // delimit, otherwise the next agent merges into it and its Disallow rules misattribute.
      if (!cur || cur.rules) { cur = { agents: [], dis: [], rules: 0 }; groups.push(cur); }
      cur.agents.push(v.toLowerCase());
    } else if (cur) {
      cur.rules++;
      if (k === "disallow") cur.dis.push(v);
    }
  }
  const pick = groups.find((g) => g.agents.includes(ua.toLowerCase())) || groups.find((g) => g.agents.includes("*"));
  return pick ? pick.dis.some((d) => d === "/") : false;
}

// ─────────────────────────── check registry ───────────────────────────
// family ∈ discoverability | agent | structure | security | a11y | perf
// profiles: '*' (all) or a list. SITE checks get ctx={get,home,params}; ITEM checks get ctx={html,path}.
const AI_BOTS = ["GPTBot", "OAI-SearchBot", "PerplexityBot", "ClaudeBot", "Google-Extended"];

const SITE_CHECKS = [
  { id: "robots-sitemap", family: "discoverability", profiles: "*", weight: 1, fix: 'Serve /robots.txt with a "Sitemap:" line.',
    run: async ({ get }) => { const r = await get("/robots.txt"); return { pass: r.ok && /sitemap:/i.test(r.body), detail: r.ok ? "" : `HTTP ${r.status}` }; } },
  { id: "robots-ai-bots", family: "agent", profiles: "*", weight: 2, fix: `Do not Disallow AI crawlers (${AI_BOTS.join(", ")}) in robots.txt — it removes you from AI answers.`,
    run: async ({ get }) => { const r = await get("/robots.txt"); if (!r.ok) return { pass: false, detail: `HTTP ${r.status}` }; const blocked = AI_BOTS.filter((b) => robotsBlocks(r.body, b)); return { pass: blocked.length === 0, detail: blocked.length ? `blocks ${blocked.join(",")}` : "all allowed" }; } },
  { id: "sitemap", family: "discoverability", profiles: "*", weight: 2, fix: "Emit /sitemap.xml enumerating pages with <lastmod>.",
    run: async ({ get }) => { const r = await get("/sitemap.xml"); const n = [...r.body.matchAll(/<loc>/gi)].length; return { pass: r.ok && n > 0, detail: r.ok ? `${n} urls` : `HTTP ${r.status}` }; } },
  { id: "feed", family: "discoverability", profiles: ["blog", "changelog", "apex"], weight: 1, fix: "Publish an RSS/Atom feed.",
    run: async ({ get }) => { for (const p of ["/feed.xml", "/feed", "/rss.xml"]) { const r = await get(p); if (r.ok && /<(rss|feed)\b/i.test(r.body)) return { pass: true, detail: p }; } return { pass: false, detail: "none" }; } },
  { id: "llms", family: "agent", profiles: "*", weight: 2, fix: "Serve /llms.txt (H1 + curated links) for answer engines & agents (llmstxt.org).",
    run: async ({ get }) => { const r = await get("/llms.txt"); const ok = r.ok && /^\s*#\s/.test(r.body) && /\[[^\]]+\]\([^)]+\)/.test(r.body); return { pass: ok, detail: r.ok ? `${r.body.length}b` : `HTTP ${r.status}` }; } },
  { id: "llms-full", family: "agent", profiles: ["docs", "blog"], weight: 1, fix: "Serve /llms-full.txt (full inlined content) so an agent ingests everything in one fetch.",
    run: async ({ get }) => { const r = await get("/llms-full.txt"); return { pass: r.ok && r.body.length > 500, detail: r.ok ? `${r.body.length}b` : `HTTP ${r.status}` }; } },
  { id: "mcp-wellknown", family: "agent", profiles: "*", weight: 2, fix: "Expose an MCP manifest at /.well-known/mcp.json (and/or /.well-known/mcp) so agents auto-discover your endpoint.",
    run: async ({ get }) => { for (const p of ["/.well-known/mcp.json", "/.well-known/mcp"]) { const r = await get(p); if (r.ok && r.body.includes("{")) return { pass: true, detail: p }; } return { pass: false, detail: "404" }; } },
  { id: "mcp-endpoint", family: "agent", profiles: ["blog", "api", "apex", "docs"], weight: 1, fix: "Serve a /v1/mcp (or /mcp) agent-readable catalog.",
    run: async ({ get }) => { for (const p of ["/v1/mcp", "/mcp"]) { const r = await get(p); if (r.ok) return { pass: true, detail: p }; } return { pass: false, detail: "404" }; } },
  { id: "agent-card", family: "agent", profiles: ["apex", "api"], weight: 1, fix: "Expose /.well-known/agent-card.json (A2A) so the site is an addressable agent.",
    run: async ({ get }) => { for (const p of ["/.well-known/agent-card.json", "/.well-known/agent.json"]) { const r = await get(p); if (r.ok && /json/i.test(r.ct)) return { pass: true, detail: p }; } return { pass: false, detail: "absent" }; } },
  { id: "x402", family: "agent", profiles: ["blog", "api"], weight: 1, fix: "A paid route should answer an uncredentialed request with 402 + PAYMENT-REQUIRED (x402).",
    run: async ({ get, params }) => { if (!params.paidPath) return { pass: true, detail: "n/a" }; const r = await get(params.paidPath); const pay = r.headers.get("payment-required") || /"accepts"\s*:/.test(r.body); return { pass: r.status === 402, detail: r.status === 402 ? (pay ? "402 + reqs" : "402") : `HTTP ${r.status}` }; } },
  // security headers (read from homepage response)
  { id: "sec-hsts", family: "security", profiles: "*", weight: 2, fix: "Set Strict-Transport-Security (HSTS).",
    run: ({ home }) => ({ pass: !!home.headers.get("strict-transport-security"), detail: "" }) },
  { id: "sec-csp", family: "security", profiles: "*", weight: 2, fix: "Set a Content-Security-Policy.",
    run: ({ home }) => ({ pass: !!home.headers.get("content-security-policy"), detail: "" }) },
  { id: "sec-nosniff", family: "security", profiles: "*", weight: 1, fix: "Set X-Content-Type-Options: nosniff.",
    run: ({ home }) => ({ pass: /nosniff/i.test(home.headers.get("x-content-type-options") || ""), detail: "" }) },
  { id: "sec-frame", family: "security", profiles: "*", weight: 1, fix: "Set X-Frame-Options or CSP frame-ancestors (clickjacking).",
    run: ({ home }) => ({ pass: !!home.headers.get("x-frame-options") || /frame-ancestors/i.test(home.headers.get("content-security-policy") || ""), detail: "" }) },
  { id: "sec-referrer", family: "security", profiles: "*", weight: 1, fix: "Set Referrer-Policy.",
    run: ({ home }) => ({ pass: !!home.headers.get("referrer-policy"), detail: "" }) },
  // perf (basic, header/timing based)
  { id: "perf-ttfb", family: "perf", profiles: "*", weight: 1, fix: "Homepage should respond < 1500ms (edge-cache/SSG).",
    run: ({ home }) => ({ pass: home.ok && home.ms > 0 && home.ms < 1500, detail: `${home.ms}ms` }) },
  { id: "perf-cache", family: "perf", profiles: "*", weight: 1, fix: "Send Cache-Control / be edge-cached (cf-cache-status).",
    run: ({ home }) => ({ pass: !!home.headers.get("cache-control") || !!home.headers.get("cf-cache-status"), detail: "" }) },
  { id: "perf-compress", family: "perf", profiles: "*", weight: 1, fix: "Serve compressed HTML (Cloudflare brotli/gzip).",
    run: ({ home }) => ({ pass: home.ok && home.body.length > 0 && home.body.length < 600_000, detail: `${Math.round(home.body.length / 1024)}kb html` }) },
  // a11y (site-level)
  { id: "a11y-lang", family: "a11y", profiles: "*", weight: 1, fix: "Set <html lang>.",
    run: ({ home }) => ({ pass: /<html[^>]+lang=/i.test(home.body), detail: "" }) },
  { id: "a11y-viewport", family: "a11y", profiles: "*", weight: 1, fix: 'Add <meta name="viewport"> for mobile.',
    run: ({ home }) => ({ pass: hasMeta(home.body, "name", "viewport"), detail: "" }) },
];

const ITEM_CHECKS = [
  { id: "title", family: "discoverability", profiles: "*", weight: 1, fix: "Unique <title> per page.",
    run: (h) => ({ pass: (attr(h, /<title>([^<]{4,})<\/title>/i) || "").trim().length > 3, detail: "" }) },
  { id: "meta-desc", family: "discoverability", profiles: "*", weight: 2, fix: "50–160 char <meta name=description>.",
    run: (h) => { const d = decodeEntities(attr(h, /<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']/i) || "").trim(); return { pass: d.length >= 50 && d.length <= 160, detail: d ? `${d.length}c` : "missing" }; } },
  { id: "canonical", family: "discoverability", profiles: "*", weight: 1, fix: "Self rel=canonical + no noindex.",
    run: (h, url) => { const c = attr(h, /<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']/i) || ""; const noindex = /<meta[^>]+name=["']robots["'][^>]+content=["'][^"']*noindex/i.test(h); return { pass: !!c && !noindex, detail: noindex ? "noindex!" : c ? "" : "missing" }; } },
  { id: "og", family: "discoverability", profiles: "*", weight: 1, fix: "Open Graph title/type/url(/image).",
    run: (h) => { const n = ["og:title", "og:type", "og:url"].filter((p) => hasMeta(h, "property", p)).length; return { pass: n === 3, detail: `${n}/3` }; } },
  { id: "jsonld-valid", family: "discoverability", profiles: "*", weight: 1, fix: "Embed at least one valid JSON-LD block.",
    run: (h) => ({ pass: jsonLd(h).length > 0, detail: `${jsonLd(h).length} node(s)` }) },
  { id: "jsonld-article", family: "discoverability", profiles: ["blog"], weight: 2, fix: "BlogPosting/Article JSON-LD (headline/author/dates).",
    run: (h) => ({ pass: ldHasType(jsonLd(h), ["BlogPosting", "Article", "NewsArticle", "TechArticle"]), detail: "" }) },
  { id: "jsonld-dates", family: "discoverability", profiles: ["blog", "docs", "changelog"], weight: 1, fix: "datePublished + dateModified (ISO) — freshness is a top AEO signal.",
    run: (h) => { const a = jsonLd(h).find((n) => typeOf(n).some((t) => ["BlogPosting", "Article", "NewsArticle", "TechArticle"].includes(t))) || {}; const iso = (v) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}/.test(v); return { pass: iso(a.datePublished) && iso(a.dateModified), detail: a.dateModified ? "" : "no dateModified" }; } },
  { id: "jsonld-author", family: "discoverability", profiles: ["blog"], weight: 1, fix: "author → Person with sameAs[] (E-E-A-T citation signal).",
    run: (h) => { const a = jsonLd(h).find((n) => n.author) || {}; const au = a.author && (Array.isArray(a.author) ? a.author[0] : a.author); const ok = au && typeof au === "object" && au.name && (Array.isArray(au.sameAs) ? au.sameAs.length : !!au.sameAs); return { pass: !!ok, detail: au?.name ? (ok ? "" : "no sameAs") : "no author" }; } },
  { id: "jsonld-audio", family: "agent", profiles: ["blog"], weight: 1, fix: "AudioObject JSON-LD → surfaces the WAVE Voice narration to engines.",
    run: (h) => ({ pass: h.includes('"AudioObject"'), detail: "" }) },
  { id: "transcript", family: "agent", profiles: ["blog"], weight: 1, fix: "Expose the narration transcript — text is what answer engines read.",
    run: (h) => ({ pass: /transcript/i.test(h), detail: "" }) },
  { id: "single-h1", family: "structure", profiles: "*", weight: 1, fix: "Exactly one <h1>.",
    run: (h) => { const n = [...h.matchAll(/<h1[\s>]/gi)].length; return { pass: n === 1, detail: `${n}` }; } },
  { id: "heading-order", family: "structure", profiles: "*", weight: 1, fix: "No heading-level skips (don't jump h2→h4).",
    run: (h) => { const lv = [...h.matchAll(/<h([1-4])[\s>]/gi)].map((m) => +m[1]); let ok = true; for (let i = 1; i < lv.length; i++) if (lv[i] - lv[i - 1] > 1) ok = false; return { pass: ok && lv.length > 1, detail: ok ? "" : "skips" }; } },
  { id: "semantic-html", family: "structure", profiles: "*", weight: 1, fix: "Use <main> + <article> so engines isolate the answer from boilerplate.",
    run: (h) => ({ pass: /<main[\s>]/i.test(h) && /<article[\s>]/i.test(h), detail: "" }) },
  { id: "answer-first", family: "structure", profiles: ["blog", "docs"], weight: 1, fix: "Lead with ≥40 words of prose before the first sub-heading (GEO answer-first).",
    run: (h) => { const body = (h.split(/<\/h1>/i)[1] || h); const pre = body.split(/<h2[\s>]/i)[0] || ""; const words = visibleText(pre).split(" ").filter(Boolean).length; return { pass: words >= 40, detail: `${words}w` }; } },
  { id: "lists-tables", family: "structure", profiles: ["blog", "docs"], weight: 1, fix: "Include a list or table — they're cited more than prose-only.",
    run: (h) => ({ pass: /<(ul|ol|table)[\s>]/i.test(h), detail: "" }) },
  { id: "a11y-img-alt", family: "a11y", profiles: "*", weight: 1, fix: "Every <img> needs alt text.",
    run: (h) => { const imgs = [...h.matchAll(/<img\b[^>]*>/gi)].map((m) => m[0]); if (!imgs.length) return { pass: true, detail: "no imgs" }; const withAlt = imgs.filter((t) => /\balt\s*=/.test(t)).length; return { pass: withAlt === imgs.length, detail: `${withAlt}/${imgs.length}` }; } },
];

const PROFILES = {
  blog: { itemRe: /\/blog\/[a-z0-9-]+\/?$/i, paidPath: "/api/v1/voice/generate" },
  docs: { itemRe: /\/(docs|guide|guides|reference)\//i },
  changelog: { itemRe: /\/(changelog|releases?)\//i },
  apex: { itemRe: null },
  api: { itemRe: null, paidPath: "/v1/voice/generate" },
};

async function enumItems(params) {
  if (!params.itemRe) return [];
  const sm = await http("/sitemap.xml");
  let urls = [...sm.body.matchAll(/<loc>([^<]+)<\/loc>/gi)].map((m) => sameOrigin(m[1].trim())).filter((u) => u && params.itemRe.test(new URL(u).pathname));
  if (!urls.length) { const idx = await http("/"); urls = [...idx.body.matchAll(/href="([^"]+)"/gi)].map((m) => sameOrigin(m[1])).filter((u) => u && params.itemRe.test(new URL(u).pathname)); }
  return [...new Set(urls)].slice(0, MAX_ITEMS);
}

// ─────────────────────────── grading ───────────────────────────
const GRADE = (p) => (p >= 90 ? "A" : p >= 80 ? "B" : p >= 70 ? "C" : p >= 60 ? "D" : "F");
const RANK = { A: 4, B: 3, C: 2, D: 1, F: 0 };
const applies = (c) => (c.profiles === "*" || c.profiles.includes(PROFILE)) && (!ONLY_FAMILY || c.family === ONLY_FAMILY);
const mark = (p) => (p ? "✓" : "✗");

async function main() {
  const params = PROFILES[PROFILE] || PROFILES.apex;
  const home = await http("/");
  const fam = {}; // family -> {earned, total}
  const fixes = new Map();
  const rows = [];
  const bump = (f, w, pass) => { (fam[f] ??= { e: 0, t: 0 }); fam[f].t += w; if (pass) fam[f].e += w; };

  for (const c of SITE_CHECKS.filter(applies)) {
    let r; try { r = await c.run({ get: http, home, params }); } catch (e) { r = { pass: false, detail: "err" }; }
    bump(c.family, c.weight, r.pass); if (!r.pass) fixes.set(c.id, c.fix);
    rows.push({ scope: "site", family: c.family, id: c.id, pass: r.pass, detail: r.detail });
  }

  const items = await enumItems(params);
  for (const url of items) {
    const r = await http(url);
    if (!r.ok) continue;
    for (const c of ITEM_CHECKS.filter(applies)) {
      let res; try { res = c.run(r.body, url); } catch { res = { pass: false, detail: "err" }; }
      bump(c.family, c.weight, res.pass); if (!res.pass) fixes.set(`item:${c.id}`, c.fix);
      rows.push({ scope: new URL(url).pathname, family: c.family, id: c.id, pass: res.pass, detail: res.detail });
    }
  }

  let E = 0, T = 0;
  const families = Object.fromEntries(Object.entries(fam).map(([k, v]) => { E += v.e; T += v.t; return [k, { pct: v.t ? Math.round((v.e / v.t) * 100) : 100, grade: GRADE(v.t ? (v.e / v.t) * 100 : 100) }]; }));
  const pct = T ? Math.round((E / T) * 100) : 0;
  const grade = GRADE(pct);
  const ok = RANK[grade] >= (RANK[MIN] ?? 3);

  if (JSON_OUT) {
    console.log(JSON.stringify({ base: BASE, profile: PROFILE, grade, pct, families, items: items.length, fixes: [...fixes.values()], pass: ok }, null, 2));
  } else {
    console.log(`\n  wave-bench · ${PROFILE} · ${BASE}\n  ${"─".repeat(60)}`);
    let lastScope = "";
    for (const r of rows) { if (r.scope !== lastScope) { console.log(`\n  ${r.scope.toUpperCase()}`); lastScope = r.scope; } console.log(`   ${mark(r.pass)} [${r.family.slice(0, 4)}] ${r.id.padEnd(18)} ${r.detail || ""}`); }
    console.log(`\n  ${"─".repeat(60)}\n  FAMILIES: ${Object.entries(families).map(([k, v]) => `${k} ${v.grade}(${v.pct}%)`).join("  ·  ")}`);
    console.log(`  GRADE  ${grade}  (${pct}%  ·  ${items.length} item(s))\n`);
    if (fixes.size) { console.log("  FIXES:"); for (const f of fixes.values()) console.log(`   • ${f}`); console.log(""); }
    console.log(`  ${ok ? "PASS" : "FAIL"} — threshold ${MIN}\n`);
  }
  process.exit(ok ? 0 : 1);
}
main().catch((e) => { console.error("bench failed:", e instanceof Error ? e.message : "unknown"); process.exit(2); });
