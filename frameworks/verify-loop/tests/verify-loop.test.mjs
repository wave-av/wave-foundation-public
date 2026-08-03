import { test } from "node:test";
import assert from "node:assert/strict";
import {
  selfTest, existsByStatus, mapLimit, verdict, scrubSecrets, probe, runChecks,
} from "../verify-loop.mjs";

test("hermetic self-test passes (the loop verifies itself)", async () => {
  const { ok, results } = await selfTest();
  const failed = results.filter((r) => !r.ok).map((r) => r.name);
  assert.equal(ok, true, `failing checks: ${failed.join(", ")}`);
});

test("existsByStatus rejects 404/5xx — a can-only-pass gate would fail here", () => {
  assert.equal(existsByStatus(404), false);
  assert.equal(existsByStatus(500), false);
  assert.equal(existsByStatus(402), true, "a documented paid route 402s and is healthy");
  assert.equal(existsByStatus(308), true);
});

test("probe enforces the SSRF guards (injected fetch, no network)", async () => {
  const ftp = await probe("ftp://x.test/a", { fetchImpl: async () => ({ status: 200 }) });
  assert.equal(ftp.ok, false);
  assert.match(ftp.error, /bad-protocol/);
  const creds = await probe("https://u:p@x.test/a", { fetchImpl: async () => ({ status: 200 }) });
  assert.equal(creds.error, "credentials-in-url");
  const r301 = await probe("https://x.test/r", { fetchImpl: async () => ({ status: 301 }) });
  assert.equal(r301.ok, true, "3xx proves life but is not chased");
});

test("mapLimit preserves order and bounds concurrency", async () => {
  let inFlight = 0;
  let max = 0;
  const out = await mapLimit([1, 2, 3, 4, 5], 2, async (x) => {
    inFlight++; max = Math.max(max, inFlight);
    await new Promise((r) => setTimeout(r, 3));
    inFlight--; return x + 1;
  });
  assert.deepEqual(out, [2, 3, 4, 5, 6]);
  assert.ok(max <= 2, `concurrency exceeded: ${max}`);
});

test("verdict refuses on a single red", () => {
  const v = verdict([{ name: "a", ok: true }, { name: "b", ok: false, detail: "404" }]);
  assert.equal(v.ok, false);
  assert.equal(v.fail, 1);
  assert.equal(v.red[0].name, "b");
});

test("scrubSecrets redacts keys + masks opaque tokens, spares slugs/urls", () => {
  const s = scrubSecrets({
    apiKey: "x",
    token: "abcd1234abcd1234abcd1234abcd",
    slug: "agent-commerce",
    url: "https://docs.wave.online/docs/mcp",
  });
  assert.equal(s.apiKey, "[redacted]");
  assert.equal(s.token, "[redacted]");
  assert.equal(s.slug, "agent-commerce");
  assert.equal(s.url, "https://docs.wave.online/docs/mcp");
});

test("runChecks ties probe→verdict→provenance with no secret leak", async () => {
  const fakeFetch = async (href) => ({ status: href.includes("missing") ? 404 : 200 });
  const { verdict: v, provenance: p } = await runChecks(
    [{ name: "ok", url: "https://x.test/a" }, { name: "bad", url: "https://x.test/missing" }],
    { tool: "test", fetchImpl: fakeFetch },
  );
  assert.equal(v.ok, false);
  assert.equal(v.fail, 1);
  assert.equal(p.tool, "test");
  assert.ok(p.verify_loop, "provenance carries the primitive version");
});
