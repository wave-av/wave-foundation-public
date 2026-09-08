// Regression drill for CodeQL js/bad-tag-filter in frameworks/bench/bench.mjs's `visibleText()` /
// `jsonLd()` tag-stripping. bench.mjs is a fleet-wide vendored SSoT (wave-blog-www's
// bench-ssot-drift.yml diffs it byte-for-byte against a raw-GitHub fetch), so it MUST remain one
// self-contained file — these tests live here, separately, and only IMPORT the two functions
// (bench.mjs exports them + guards its `main()` CLI entrypoint behind an `import.meta.url` check,
// the same idiom already used by plugin/hooks/intent-ledger.mjs and frameworks/verify-loop/
// verify-loop.mjs, so importing this file never fires a network call).
//
// Each `visibleText` case below was measured, before writing this file, against the OLD regex
// family (`/<script[\s\S]*?<\/script>/gi` etc.) via a throwaway copy of the pre-fix functions. Two
// independent lanes this week found that the "obvious" facet-1 example `<scripter>hello</scripter>
// WORLD` does NOT discriminate (old code already returns "hello WORLD" — there is no later exact
// `</script>` for the lazy regex to latch onto). The inputs here are the ones that DO discriminate,
// confirmed against the OLD implementation:
//
//   facet                          OLD visibleText()        NEW visibleText()
//   ------------------------------ ------------------------- -------------------------
//   1  no \b on open tag           "PREFIX SUFFIX"           "PREFIX MIDDLE SUFFIX"
//   2  rigid literal close tag     "PREFIX MIDDLE SUFFIX"    "PREFIX SUFFIX"
//   3  close tag rejects space     "PREFIX MIDDLE SUFFIX"    "PREFIX SUFFIX"
//   4  unclosed <script> leaks     "PREFIX MIDDLE ... LEAKS" "PREFIX"
//
// and for jsonLd() (facet 5 — same rigid `<\/script>` close reused in the ld+json extractor):
//
//   facet                          OLD jsonLd()   NEW jsonLd()
//   ------------------------------ -------------- ----------------
//   5a attributed close tag        []             [{"a":1}]
//   5b whitespace in close tag     []             [{"a":1}]
//
// See the PR body for the full per-facet OLD/NEW table and the mutation-drill results.
import test from "node:test";
import assert from "node:assert/strict";
import { visibleText, jsonLd } from "./bench.mjs";

// ─────────────────────────── facet 1: word-boundary on the OPEN tag ───────────────────────────
test("visibleText: <scripter> is not misread as <script> even with a later exact </script>", () => {
  // OLD: "PREFIX SUFFIX" (MIDDLE swallowed by the lazy regex latching onto the later </script>).
  const out = visibleText("PREFIX<scripter>MIDDLE</script>SUFFIX");
  assert.equal(out, "PREFIX MIDDLE SUFFIX");
});

// ─────────────────────────── facet 2: close tag tolerates attributes ───────────────────────────
test("visibleText: an attributed close tag (</script foo=\"bar\">) still closes the block", () => {
  // OLD: "PREFIX MIDDLE SUFFIX" (the rigid literal close never matches, so MIDDLE leaks as if it
  // were ordinary page prose — the exact class CodeQL js/bad-tag-filter flags).
  const out = visibleText('PREFIX<script>MIDDLE</script foo="bar">SUFFIX');
  assert.equal(out, "PREFIX SUFFIX");
});

// ─────────────────────────── facet 3: close tag tolerates whitespace ───────────────────────────
test('visibleText: a close tag with whitespace (</script >) still closes the block', () => {
  // OLD: "PREFIX MIDDLE SUFFIX" (same leak as facet 2 — CodeQL's own example).
  const out = visibleText("PREFIX<script>MIDDLE</script >SUFFIX");
  assert.equal(out, "PREFIX SUFFIX");
});

// ─────────────────────────── facet 4: unclosed block fails CLOSED ───────────────────────────
test("visibleText: an unclosed <script> consumes to end-of-string instead of leaking the tail", () => {
  // OLD: "PREFIX MIDDLE STILL-IN-SCRIPT SUFFIX-LEAKS" (no close anywhere => the whole regex fails
  // to match => nothing is stripped => every byte after <script> leaks as visible text).
  const out = visibleText("PREFIX<script>MIDDLE STILL-IN-SCRIPT SUFFIX-LEAKS");
  assert.equal(out, "PREFIX");
});

// ─────────────────────────── style / nav / footer / header still strip (non-regression) ─────
test("visibleText: <style> and <nav>/<footer>/<header> blocks are still excised", () => {
  const html =
    "<style>.x{color:red}</style><nav>Home About</nav><header>Site Title</header>" +
    "<main><article><h1>T</h1><p>Real content here</p></article></main>" +
    "<footer>Copyright 2026</footer>";
  const out = visibleText(html);
  assert.ok(!/color:red/.test(out), "style body must not leak");
  assert.ok(!/Home About/.test(out), "nav body must not leak");
  assert.ok(!/Site Title/.test(out), "header body must not leak");
  assert.ok(!/Copyright/.test(out), "footer body must not leak");
  assert.ok(/Real content here/.test(out), "article body must survive");
});

// ─────────────────────────── ordinary well-formed script (non-regression) ───────────────────
test("visibleText: an ordinary well-formed <script> block is still fully excised", () => {
  const out = visibleText("<p>Hello</p><script>var x = 1; if (x < 2) { /* </notreal> */ }</script><p>World</p>");
  assert.equal(out, "Hello World");
});

// ─────────────────────────── jsonLd facet 5: rigid close tag reused from visibleText ────────
test("jsonLd: an attributed close tag (</script foo=\"bar\">) does not swallow the ld+json block", () => {
  // OLD: [] (the literal `<\/script>` in the matchAll regex never matches, so the block is never
  // captured at all — the check this feeds, jsonld-valid, would silently read as "no JSON-LD").
  const out = jsonLd('PRE<script type="application/ld+json">{"a":1}</script foo="bar">POST');
  assert.deepEqual(out, [{ a: 1 }]);
});

test("jsonLd: a close tag with whitespace (</script >) does not swallow the ld+json block", () => {
  // OLD: [] (same rigid-close defect).
  const out = jsonLd('PRE<script type="application/ld+json">{"a":1}</script >POST');
  assert.deepEqual(out, [{ a: 1 }]);
});

// ─────────────────────────── jsonLd baseline behavior (non-regression) ──────────────────────
test("jsonLd: extracts multiple valid blocks and skips a malformed one", () => {
  const html =
    '<script type="application/ld+json">{"@type":"BlogPosting","headline":"H"}</script>' +
    '<script type="application/ld+json">not json at all</script>' +
    '<script type="application/ld+json">[{"@type":"Person","name":"A"}]</script>';
  const out = jsonLd(html);
  assert.equal(out.length, 2);
  assert.equal(out[0].headline, "H");
  assert.equal(out[1].name, "A");
});

test("jsonLd: a @graph wrapper is expanded into its member nodes", () => {
  const html =
    '<script type="application/ld+json">{"@graph":[{"@type":"A"},{"@type":"B"}]}</script>';
  const out = jsonLd(html);
  assert.equal(out.length, 2);
});
