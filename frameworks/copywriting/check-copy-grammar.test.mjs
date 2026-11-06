// check-copy-grammar.test.mjs — both-directions drill for check-copy-grammar.mjs.
// Every rule has a FIRES arm (the live defect that motivated it) and a STAYS-SILENT arm (the
// legitimate shape that looks similar). Law: a gate is tested in both directions.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { lintSource, htmlToText } from "./check-copy-grammar.mjs";
import { RULES } from "./copy-grammar-rules.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const GATE = join(HERE, "check-copy-grammar.mjs");

const rules = (src, file = "copy.ts") => lintSource(src, file).map((f) => f.rule);
const has = (src, rule, file) => assert.ok(rules(src, file).includes(rule), `${rule} should fire on: ${src}`);
const not = (src, rule, file) => assert.ok(!rules(src, file).includes(rule), `${rule} should stay silent on: ${src}`);

test("count-noun-agreement fires on the live hero kicker and stays silent on the plural", () => {
  has(`export const kicker = "Built for two kinds of user: people and agents";`, "count-noun-agreement");
  has(`const h = "Build on media infrastructure made for both kinds of user.";`, "count-noun-agreement");
  has(`const h = "The internet has two kinds of user now: people and agents.";`, "count-noun-agreement");
  not(`const h = "Built for two kinds of users: people and agents";`, "count-noun-agreement");
  not(`const h = "Paid per call by either kind of user: x402 for agents.";`, "count-noun-agreement");
  not(`const h = "both user and agent traffic share one route";`, "count-noun-agreement"); // adjectival
  has(`const h = "used the same way by two kinds of caller. A person calls with a key.";`, "count-noun-agreement");
  not(`const css = ".btn{color:var(--acc);text-transform:uppercase} .kinds of user{}";`, "count-noun-agreement"); // CSS
  has(`const md = \`## Concepts\nUsed by two kinds of caller. A person calls; an agent pays: {x}\n\`;`, "count-noun-agreement");
});

test("cta-caps fires on ALL-CAPS and Title Case labels, stays silent on acronyms and sentence case", () => {
  has(`<a class="btnp" href="/signup">GET API KEY</a>`, "cta-caps", "nav.html");
  has(`const s = \`<a class="btn" href="/k">GET API KEY</a>\`;`, "cta-caps");
  has(`<p className="mono-meta uppercase">\n  WHAT YOU GET\n</p>`, "cta-caps", "Form.tsx");
  has(`const cta = { label: "Get API Key", href: "/keys" };`, "cta-caps");
  has(`const cta = { primaryLabel: "Talk To Sales" };`, "cta-caps");
  not(`const cta = { label: "Get API key", href: "/keys" };`, "cta-caps");
  not(`const cta = { label: "Sign in" };`, "cta-caps");
  not(`const cta = { label: "The Money Engine" };`, "cta-caps"); // product name
  not(`const x = ["SDK EULA", "DMCA", "SDI · HDMI", "TTML / IMSC"];`, "cta-caps");
  not(`const line = "< HTTP/2 200 OK";`, "cta-caps");
  not(`const id = "GET_API_KEY";`, "cta-caps"); // identifier
});

test("api-term-case fires on the lowercase term and stays silent on hosts, paths and keyword lists", () => {
  has(`const p = "Create an api key in the console.";`, "api-term-case");
  has(`const p = "The Api returns a receipt.";`, "api-term-case");
  not(`const p = "Create an API key in the console.";`, "api-term-case");
  not(`const p = "Call api.wave.online or /api/v1 with your apiKey.";`, "api-term-case");
  not(`const c = { keywords: "api reference endpoints" };`, "api-term-case");
});

test("login-verb-noun fires on noun-as-verb and verb-as-modifier, stays silent on correct forms", () => {
  has(`const p = "Please login to continue.";`, "login-verb-noun");
  has(`const p = "You can signup with a card.";`, "login-verb-noun");
  has(`const p = "Open the sign in page.";`, "login-verb-noun");
  not(`const p = "Please log in to continue.";`, "login-verb-noun");
  not(`const p = "Open the sign-in page. Your login expired.";`, "login-verb-noun");
  not(`const p = "Sign in to the WAVE console";`, "login-verb-noun");
});

test("oxford-comma warns on a missing serial comma and stays silent on clauses and appositives", () => {
  has(`const p = "Moves video, audio and captions on one clock.";`, "oxford-comma");
  not(`const p = "Moves video, audio, and captions on one clock.";`, "oxford-comma");
  not(`const p = "At WAVE, people and agents pay per call.";`, "oxford-comma"); // clause
  not(`const p = "both kinds of users, people and agents, discover it";`, "oxford-comma"); // appositive
  assert.equal(RULES["oxford-comma"].severity, "warn");
});

test("double-space fires in prose strings and stays silent in code samples and templates", () => {
  has(`const p = "One call shape.  Every transport.";`, "double-space");
  has(`{"body": "Paid per call.  Per stream."}`, "double-space", "copy.json");
  not(`const c = { code: "GET https://api.wave.online/v1  ·  x402" };`, "double-space");
  not(`const l = "Authorization: Bearer <key>   (or x402)";`, "double-space");
  not(`const t = \`<p>One call.</p>   <p>Every transport.</p>\`;`, "double-space");
});

test("string-whitespace fires on padded prose and stays silent on concatenation, class lists and JSX spacing", () => {
  has(`const t = { title: " Sign in to the WAVE console" };`, "string-whitespace");
  has(`const t = { title: "Sign in to the WAVE console " };`, "string-whitespace");
  not(`const t = "one call shape moves media across every transport, and " + "both kinds of users";`, "string-whitespace");
  not(`<div className="flex items-center gap-2 ">x</div>`, "string-whitespace", "A.tsx");
  not(`<p>{state}{" It has expired"}</p>`, "string-whitespace", "A.tsx");
  not(`const code = "  ▸ render job accepted — poll /v1/render";`, "string-whitespace"); // terminal mockup
});

test("em-dash-budget warns above the budget and respects --strict-em-dash and --em-dash-max", () => {
  const two = `const a = "One — two."; const b = "Three — four.";`;
  const f = lintSource(two, "copy.ts");
  assert.equal(f.filter((x) => x.rule === "em-dash-budget")[0]?.severity, "warn");
  assert.equal(lintSource(two, "copy.ts", { strictEmDash: true }).find((x) => x.rule === "em-dash-budget").severity, "error");
  assert.equal(lintSource(two, "copy.ts", { emDashMax: 2 }).some((x) => x.rule === "em-dash-budget"), false);
});

test("comments are never judged as copy; copy-grammar-ignore suppresses one line", () => {
  not(`// the old kicker said "two kinds of user" — do not bring it back\nconst k = "ok";`, "count-noun-agreement");
  not(`/* GET API KEY was the defect */ const k = "ok";`, "cta-caps");
  not(`const k = "two kinds of user"; // copy-grammar-ignore: count-noun-agreement`, "count-noun-agreement");
  not(`// copy-grammar-ignore\nconst k = "two kinds of user";`, "count-noun-agreement");
  has(`const k = "two kinds of user"; // copy-grammar-ignore: cta-caps`, "count-noun-agreement"); // wrong rule id
});

test("htmlToText strips <script> blocks even with browser-tolerant (non-well-formed) end tags — CodeQL js/bad-tag-filter", () => {
  // POSITIVE CONTROL that a naive /<script[\s\S]*?<\/script>/ CANNOT pass: the browser accepts
  // </script foo="bar"> and </script > as end tags even though they are parser errors, and a
  // regex that only matches the exact literal </script> leaks this content into extracted copy.
  assert.equal(htmlToText(`<script>doNotShipThis()</script foo="bar">Real prose here.`).trim(), "Real prose here.");
  assert.equal(htmlToText(`<script>doNotShipThis()</script >Real prose here.`).trim(), "Real prose here.");
  // Case-insensitivity (browsers accept upper/mixed-case tag names).
  assert.equal(htmlToText(`<SCRIPT>doNotShipThis()</SCRIPT>Real prose here.`).trim(), "Real prose here.");
  // Regression control: the well-formed, lower-case shape must still be stripped.
  assert.equal(htmlToText(`<script>doNotShipThis()</script>Real prose here.`).trim(), "Real prose here.");
  // Attributes on the opening tag.
  assert.equal(htmlToText(`<script type="text/javascript">doNotShipThis()</script>Real prose here.`).trim(), "Real prose here.");
  // style blocks use the same helper — cover the same malformed-close-tag case.
  assert.equal(htmlToText(`<style>.x{color:red}</style foo="bar">Real prose here.`).trim(), "Real prose here.");
  // A script with no closing tag at all must never leak its content as copy either.
  assert.equal(htmlToText(`<script>doNotShipThis()`).trim(), "");
});

test("CLI: exits 1 on an error-severity finding, 0 when clean or --warn-only, 2 on usage", () => {
  const dir = mkdtempSync(join(tmpdir(), "copy-grammar-"));
  writeFileSync(join(dir, "red.ts"), `export const kicker = "Built for two kinds of user: people and agents";\n`);
  writeFileSync(join(dir, "green.ts"), `export const kicker = "Built for two kinds of users: people and agents";\n`);
  writeFileSync(join(dir, "red.test.ts"), `export const k = "GET API KEY";\n`); // test files are skipped
  const run = (...a) => spawnSync(process.execPath, [GATE, ...a], { encoding: "utf8", cwd: dir });
  const red = run(join(dir, "red.ts"), "--root", dir);
  assert.equal(red.status, 1);
  assert.match(red.stdout, /red\.ts:1:\d+ \[error\] count-noun-agreement/);
  assert.equal(run(join(dir, "green.ts"), "--root", dir).status, 0);
  assert.equal(run(dir, "--root", dir, "--warn-only").status, 0);
  assert.equal(run(dir, "--root", dir, "--rules", "cta-caps").status, 0); // red.test.ts skipped, red.ts has no caps
  const j = JSON.parse(run(dir, "--root", dir, "--json").stdout);
  assert.equal(j.errors, 1);
  assert.equal(j.files, 2);
  assert.equal(run().status, 2);
  assert.equal(run("--list-rules").status, 0);
});
