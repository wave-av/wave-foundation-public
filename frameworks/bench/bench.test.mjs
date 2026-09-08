// Drill for js/bad-tag-filter (CodeQL alert, frameworks/bench/bench.mjs:100): visibleText() must
// strip <script>/<style> blocks regardless of case, and must not leak an inline script's payload
// into the word-count text it hands to the answer-first quality check.
//
// Positive control: an UPPERCASE `<SCRIPT SRC="x">...</SCRIPT>` (a naive case-sensitive filter is
// blind to this — the defect class this alert names) MUST be excluded, and a plain lowercase
// `<script>...</script>` MUST also be excluded, while ordinary prose around them MUST survive.
// This test is written to FAIL against the pre-fix regex-only implementation and PASS against the
// post-fix enumerate-then-locate implementation (verified in the PR diff history, not reproduced
// here: re-vendoring the flagged pre-fix regex as live code — even inside a test — recreates the
// exact js/bad-tag-filter pattern CodeQL flags, so the discrimination proof lives in review, not
// in this file).
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
  // Whitespace directly before the closing angle bracket of a close tag is valid HTML that a
  // literal close-tag regex does not match, so the old single-regex implementation ran past this
  // boundary looking for the next literal occurrence. The fix must not do that (fixture below).
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
  // A close tag carrying attributes is a parser-error close browsers still accept. A close
  // pattern that only tolerates whitespace rejects this and leaks the payload (fixture below).
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

// Note: an earlier revision of this test file re-vendored the flagged pre-fix regex here as a
// "control" to prove the tests above are discriminating (fail on old code, pass on new). CodeQL
// correctly flagged that as a new js/bad-tag-filter instance: reproducing incomplete tag-stripping
// regex as live, matchable code is the defect class, regardless of whether it is reachable from
// untrusted input. The discrimination proof now lives in code review / PR history instead of as
// checked-in source: the "malformed close tag" test above is the one that actually exercises the
// fix, and it was confirmed against the pre-fix implementation before this file was committed.
