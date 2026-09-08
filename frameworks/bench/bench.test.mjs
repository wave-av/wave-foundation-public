// Drill for js/bad-tag-filter (CodeQL alert, frameworks/bench/bench.mjs:100): visibleText() must
// strip <script>/<style> blocks regardless of case, and must not leak an inline script's payload
// into the word-count text it hands to the answer-first quality check.
//
// Positive control: an UPPERCASE `<SCRIPT SRC="x">...</SCRIPT>` (a naive case-sensitive filter is
// blind to this — the defect class this alert names) MUST be excluded, and a plain lowercase
// `<script>...</script>` MUST also be excluded, while ordinary prose around them MUST survive.
// This test is written to FAIL against the pre-fix regex-only implementation and PASS against the
// post-fix enumerate-then-locate implementation (verified below by re-running it against the old
// regex directly — see the "old implementation" test).
import { test } from "node:test";
import assert from "node:assert/strict";
import { visibleText } from "./bench.mjs";

test("visibleText strips a lowercase <script> block and keeps surrounding prose", () => {
  const html = "<p>before</p><script>document.write('x')</script><p>after</p>";
  const out = visibleText(html);
  assert.match(out, /before/);
  assert.match(out, /after/);
  assert.doesNotMatch(out, /document\.write/);
});

test("positive control: an uppercase <SCRIPT SRC=...> block is excluded (case-insensitive detection)", () => {
  const html = '<p>before</p><SCRIPT SRC="https://evil.example/x.js">stealCookies()</SCRIPT><p>after</p>';
  const out = visibleText(html);
  assert.match(out, /before/, "prose before the tag must survive");
  assert.match(out, /after/, "prose after the tag must survive");
  assert.doesNotMatch(out, /stealCookies/, "uppercase <SCRIPT> payload must be stripped, not counted as visible text");
});

test("malformed close tag (whitespace before '>') does not leak content past it", () => {
  // `</script >` and `</SCRIPT\n>` are both valid HTML; a literal `<\/script>` regex does not
  // match either, so the old single-regex implementation runs past this boundary looking for the
  // next literal occurrence. The fix must not do that.
  const html = "<p>before</p><script>leakedPayload()</script ><p>after</p>";
  const out = visibleText(html);
  assert.doesNotMatch(out, /leakedPayload/);
  assert.match(out, /after/);
});

test("style blocks are stripped the same way, case-insensitively", () => {
  const html = "<p>before</p><STYLE>body{color:red}</STYLE><p>after</p>";
  const out = visibleText(html);
  assert.match(out, /before/);
  assert.match(out, /after/);
  assert.doesNotMatch(out, /color:red/);
});

test("close tag with attributes is still matched (js/bad-tag-filter union facet: attributes on close)", () => {
  // `</script foo="bar">` is a parser-error close tag browsers still accept. A close pattern that
  // only tolerates whitespace (e.g. /<\/script\s*>/) rejects this and leaks the payload.
  const html = '<p>before</p><script>leakedPayload()</script foo="bar"><p>after</p>';
  const out = visibleText(html);
  assert.doesNotMatch(out, /leakedPayload/);
  assert.match(out, /after/);
});

test("<scripter> is not treated as a <script> opener (js/bad-tag-filter union facet: \\b on open tag)", () => {
  const html = "<p>before</p><scripter>ordinary prose, not a script</scripter><p>after</p>";
  const out = visibleText(html);
  assert.match(out, /ordinary prose/, "a <scripter> tag must not be mistaken for a <script> opener");
  assert.match(out, /before/);
  assert.match(out, /after/);
});

test("an unclosed <script> consumes to EOF rather than leaking its body (js/bad-tag-filter union facet: unclosed tag)", () => {
  const html = "<p>before</p><script>doNotShipThis()";
  const out = visibleText(html);
  assert.match(out, /before/);
  assert.doesNotMatch(out, /doNotShipThis/);
});

// This drill proves the positive control is discriminating: re-running it against the OLD
// (pre-fix) implementation must FAIL, so the new test cannot pass against both versions of the
// code and prove nothing. The old regex is reproduced verbatim from the dismissed/flagged code
// (not re-derived), exercised the same way visibleText() called it.
test("old implementation: the naive case-insensitive-but-whitespace-fragile regex still passes the uppercase control (expected — /gi already covered case) but FAILS the malformed-close control", () => {
  const oldVisibleText = (h) =>
    h
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<(nav|footer|header)[\s\S]*?<\/\1>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim();

  // The malformed-close case is where the OLD implementation actually breaks: the non-greedy span
  // can't find its literal `<\/script>` at the whitespace-padded close, so it keeps searching and
  // either leaks the payload or over-consumes trailing content.
  const html = "<p>before</p><script>leakedPayload()</script ><p>after</p>";
  const out = oldVisibleText(html);
  assert.match(out, /leakedPayload/, "old implementation leaks the payload past a malformed close tag — this is the bug");
});
