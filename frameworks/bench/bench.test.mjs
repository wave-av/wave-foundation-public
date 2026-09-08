// bench.test.mjs — regression cover for CodeQL js/bad-tag-filter fix in visibleText().
// bench.mjs is a CLI script; its main() only runs when invoked directly (isMain guard), so
// importing it here for unit testing is safe and does not perform any network call.
import { test } from "node:test";
import assert from "node:assert/strict";
import { visibleText } from "./bench.mjs";

test("visibleText strips <script> blocks even with browser-tolerant (non-well-formed) end tags — CodeQL js/bad-tag-filter", () => {
  // POSITIVE CONTROL that a naive /<script[\s\S]*?<\/script>/ CANNOT pass: browsers accept
  // </script foo="bar"> and </script > as end tags even though they are parser errors, and a
  // regex that only matches the exact literal </script> leaks this content into scraped text.
  assert.equal(visibleText(`<script>doNotShipThis()</script foo="bar">Real prose here.`), "Real prose here.");
  assert.equal(visibleText(`<script>doNotShipThis()</script >Real prose here.`), "Real prose here.");
  // Case-insensitivity (browsers accept upper/mixed-case tag names).
  assert.equal(visibleText(`<SCRIPT>doNotShipThis()</SCRIPT>Real prose here.`), "Real prose here.");
  // Regression control: the well-formed, lower-case shape must still be stripped.
  assert.equal(visibleText(`<script>doNotShipThis()</script>Real prose here.`), "Real prose here.");
  // Attributes on the opening tag.
  assert.equal(visibleText(`<script type="text/javascript">doNotShipThis()</script>Real prose here.`), "Real prose here.");
});

test("visibleText still strips style/nav/footer/header and collapses whitespace (no regression)", () => {
  assert.equal(visibleText(`<style>.x{color:red}</style><nav>Home</nav><p>Real  prose  here.</p><footer>©</footer>`), "Real prose here.");
});
