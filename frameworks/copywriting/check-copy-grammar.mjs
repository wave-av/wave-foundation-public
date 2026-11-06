#!/usr/bin/env node
// check-copy-grammar.mjs — WAVE copy grammar + mechanics gate.
//
// SSOT: wave-foundation frameworks/copywriting/check-copy-grammar.mjs. Consumer repos carry a
// byte-identical copy at scripts/check-copy-grammar.mjs; edit the SSOT, then re-vendor. Do not
// fork rules locally — a rule that lives in one repo is a defect the other repos keep shipping.
//
// Born 2026-09-03 (go-live code yellow). Jake, verbatim: "there are a lot of issues regarding
// missing plurals etc — 'Built for two kinds of user: people and agents' — 'GET API KEY'".
// Live receipts that motivated each rule are cited next to the rule.
//
// What it scans: string literals, template literals and JSX/HTML text in .ts/.tsx/.js/.mjs; string
// values in .json; body text in .md/.mdx/.html. Comments, URLs, paths, CSS, class-name strings and
// identifiers are skipped — this is a COPY gate, not a code linter.
//
// Usage:
//   node check-copy-grammar.mjs <path...>              # files and/or directories (recursive)
//   node check-copy-grammar.mjs content src --json     # machine-readable findings
//   node check-copy-grammar.mjs src --warn-only        # report, never fail
//   node check-copy-grammar.mjs src --rules cta-caps,count-noun-agreement
//   node check-copy-grammar.mjs src --em-dash-max 1 --strict-em-dash
//   node check-copy-grammar.mjs --list-rules
// Exit codes: 0 clean (warnings allowed) · 1 at least one error-severity finding · 2 usage.
//
// Suppress one line: put `copy-grammar-ignore` (optionally `copy-grammar-ignore: rule-id`) in a
// comment on the SAME line or the line ABOVE. Every suppression is a receipt the reviewer sees.
//
// Zero dependencies. Never executes input, never touches the network, reads only the paths given.

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { resolve, relative, extname, basename, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { RULES, LABEL_KEY_RE, checkSegment } from "./copy-grammar-rules.mjs";

// ── Extraction ──────────────────────────────────────────────────────────────────────────────────

const CODE_EXT = new Set([".ts", ".tsx", ".js", ".mjs", ".jsx", ".cjs"]);
const TEXT_EXT = new Set([".md", ".mdx", ".html", ".htm"]);
const SKIP_DIR = new Set(["node_modules", "dist", "build", ".next", ".git", "coverage", "fixtures", ".wrangler", "generated"]);
const SKIP_FILE_RE =
  /(^|\/)(package(-lock)?\.json|tsconfig[^/]*\.json|wrangler\.[^/]+|[^/]*\.config\.[^/]+|[^/]*\.d\.ts|[^/]*\.(test|spec)\.[^/]+|[^/]*\.generated\.[^/]+|[^/]*\.min\.[^/]+|[^/]*\.snap|[^/]*lock[^/]*\.(json|yaml))$/;


// CodeQL js/bad-tag-filter: a single lazy regex like /<script[\s\S]*?<\/script>/ does NOT match
// every script end tag a browser's forgiving parser accepts — e.g. </script foo="bar"> or
// </script > (whitespace before >). Enumerate opening tags, then independently locate each one's
// close tag with a permissive (case-insensitive, attribute/whitespace-tolerant) pattern instead of
// relying on one brittle combined regex to walk the whole block.
export function stripTagBlocks(html, tag) {
  const open = new RegExp(`<${tag}\\b[^>]*>`, "gi");
  const close = new RegExp(`<\\/${tag}\\b[^>]*>`, "i");
  let out = "";
  let cursor = 0;
  let m;
  while ((m = open.exec(html))) {
    if (m.index < cursor) continue; // already consumed by a prior block
    out += html.slice(cursor, m.index);
    const tail = html.slice(m.index + m[0].length);
    const end = tail.match(close);
    cursor = end ? m.index + m[0].length + end.index + end[0].length : html.length;
    open.lastIndex = cursor;
  }
  return out + html.slice(cursor);
}

/** Replace HTML tags with a space and decode the few entities copy uses, keeping offsets loose. */
export function htmlToText(s) {
  return stripTagBlocks(stripTagBlocks(s, "script"), "style")
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&rarr;/g, "→")
    .replace(/&mdash;/g, "—");
}

/** Pull CTA texts (<a class="btn…">TEXT</a>, <button>TEXT</button>) out of an HTML fragment. */
function ctaTexts(html) {
  const out = [];
  const re = /<(a|button)\b([^>]*)>([^<]{1,80})<\/\1>/gi;
  let m;
  while ((m = re.exec(html))) {
    const attrs = m[2];
    const isCta = m[1].toLowerCase() === "button" || /class\s*=\s*["'][^"']*\b(btn|cta|button)/i.test(attrs);
    if (isCta) out.push({ text: m[3], index: m.index + m[0].indexOf(m[3]) });
  }
  return out;
}

function lineCol(src, index) {
  let line = 1;
  let last = -1;
  for (let i = 0; i < index; i++) if (src.charCodeAt(i) === 10) { line++; last = i; }
  return { line, col: index - last };
}

/**
 * Extract copy segments from source. Each segment: { text, index, kind }.
 * kind ∈ "string" | "template" | "jsx" | "cta" | "json" | "text".
 */
function extractSegments(src, ext) {
  const segs = [];
  if (TEXT_EXT.has(ext)) {
    if (ext === ".html" || ext === ".htm") {
      for (const c of ctaTexts(src)) segs.push({ text: c.text, index: c.index, kind: "cta" });
      segs.push({ text: htmlToText(src), index: 0, kind: "text", offsetsLoose: true });
    } else {
      // Markdown: drop fenced code and inline code spans (identifiers are not copy).
      const md = src.replace(/```[\s\S]*?```/g, (b) => " ".repeat(b.length)).replace(/`[^`\n]*`/g, (b) => " ".repeat(b.length));
      segs.push({ text: md, index: 0, kind: "text" });
    }
    return segs;
  }
  if (ext === ".json") {
    const re = /"((?:[^"\\]|\\.)*)"\s*(?=[,}\]\n\r])/g; // string VALUES (a key is followed by ':')
    let m;
    while ((m = re.exec(src))) {
      const raw = m[1];
      if (!raw) continue;
      const before = src.slice(Math.max(0, m.index - 3), m.index);
      if (!/[:\[,]\s*$/.test(before)) continue; // not a value position
      segs.push({ text: unescape(raw), rawText: raw, index: m.index + 1, kind: "json" });
    }
    return segs;
  }
  if (!CODE_EXT.has(ext)) return segs;

  // Blank out comments so notes-to-us are never judged as copy (line + block; offsets preserved).
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, (b) => b.replace(/[^\n]/g, " "))
    .replace(/(^|[^:'"`\\])\/\/[^\n]*/g, (b, p) => p + " ".repeat(b.length - p.length));

  // String + template literals, one pass, tracking the previous non-space char for context.
  const re = /"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'|`((?:[^`\\]|\\.)*)`/g;
  let m;
  while ((m = re.exec(code))) {
    const raw = m[1] ?? m[2] ?? m[3];
    const isTemplate = m[3] !== undefined;
    const start = m.index + 1;
    const before = code.slice(Math.max(0, m.index - 40), m.index);
    const after = code.slice(m.index + m[0].length, m.index + m[0].length + 6);
    const concat = /\+\s*$/.test(before) || /^\s*\+/.test(after);
    const attr = /(class(Name)?|style|href|src|rel|type|id|name|key|for|target|d|viewBox|fill|stroke|xmlns|lang|dir|role|http-equiv|content|property|charset|method|action|encoding|format|font|hreflang|sizes|media|crossorigin|integrity|nonce|as|imagesrcset|imagesizes)\s*[=:]\s*$/.test(before);
    const isLabel = LABEL_KEY_RE.test(before) || /aria-label\s*=\s*$/.test(before);
    const codeKey = /\b(code|snippet|cmd|command|example|curl|sh|bash|shell|pre|mono)\s*[:=]\s*$/i.test(before) || /console\.(log|error|warn|info)\(\s*$/.test(before);
    const keywordKey = /\b(keywords?|tags?|aliases|synonyms|search|kw)\s*[:=]\s*\[?\s*(?:"[^"]*",\s*)*$/.test(before);
    const jsxExpr = /\{\s*$|\?\s*$|\n\s*:\s*$/.test(before); // {" It has expired"} / ternary arms — spacing idiom
    let text = isTemplate ? raw.replace(/\$\{[^}]*\}/g, "X") : unescape(raw);
    if (isTemplate && /<[a-z!/]/i.test(text)) {
      for (const c of ctaTexts(text)) segs.push({ text: c.text, index: start + c.index, kind: "cta" });
      text = htmlToText(text);
      segs.push({ text, index: start, kind: "template", offsetsLoose: true });
      continue;
    }
    segs.push({ text, rawText: raw, index: start, kind: isTemplate ? "template" : "string", concat, attr, isLabel, codeKey, keywordKey, jsxExpr });
  }
  // JSX text nodes (.tsx/.jsx): text between tags that carries letters and no braces.
  if (ext === ".tsx" || ext === ".jsx") {
    const jre = />([^<>{}`"']*[A-Za-z][^<>{}`"']*)</g;
    while ((m = jre.exec(code))) {
      const t = m[1];
      if (!/\s/.test(t.trim()) && t.trim().length < 3) continue;
      segs.push({ text: t, index: m.index + 1, kind: "jsx" });
    }
  }
  return segs;
}

function unescape(raw) {
  return raw.replace(/\\(n|t|r|"|'|\\|`)/g, (_, c) => ({ n: "\n", t: "\t", r: "\r" })[c] ?? c);
}

// ── Driver ──────────────────────────────────────────────────────────────────────────────────────

export function lintSource(src, filePath, opts = {}) {
  const ext = extname(filePath).toLowerCase();
  const segs = extractSegments(src, ext);
  const out = [];
  const lines = src.split("\n");
  for (const seg of segs) {
    for (const f of checkSegment(seg, opts)) {
      const { line, col } = lineCol(src, Math.min(f.index, src.length - 1));
      const here = lines[line - 1] ?? "";
      const above = lines[line - 2] ?? "";
      const ig = new RegExp(`copy-grammar-ignore(?::\\s*${f.rule}(?![\\w-])|(?!\\s*:))`);
      if (ig.test(here) || (ig.test(above) && /^\s*(\/\/|\*|#|<!--|\{\/\*)/.test(above))) continue;
      out.push({ file: filePath, line, col, rule: f.rule, severity: RULES[f.rule].severity, sample: f.sample });
    }
  }
  const dashes = (segs.map((s) => s.text).join("\n").match(/—/g) ?? []).length;
  const max = opts.emDashMax ?? 1;
  if (dashes > max && (opts.rules ? opts.rules.has("em-dash-budget") : true)) {
    out.push({
      file: filePath, line: 1, col: 1, rule: "em-dash-budget",
      severity: opts.strictEmDash ? "error" : "warn",
      sample: `${dashes} em-dashes in copy (budget ${max})`,
    });
  }
  return opts.rules ? out.filter((f) => opts.rules.has(f.rule)) : out;
}

function walk(p, acc, root) {
  const abs = resolve(p);
  if (!abs.startsWith(root)) return; // never leave the root the caller named
  if (!existsSync(abs)) return;
  const st = statSync(abs);
  if (st.isDirectory()) {
    if (SKIP_DIR.has(basename(abs))) return;
    for (const e of readdirSync(abs)) walk(resolve(abs, e), acc, root);
    return;
  }
  const ext = extname(abs).toLowerCase();
  if (!CODE_EXT.has(ext) && !TEXT_EXT.has(ext) && ext !== ".json") return;
  if (SKIP_FILE_RE.test(abs.split(sep).join("/"))) return;
  acc.push(abs);
}

function main(argv) {
  const args = [...argv];
  const opt = { json: false, warnOnly: false, emDashMax: 1, strictEmDash: false, rules: null, root: process.cwd() };
  const paths = [];
  while (args.length) {
    const a = args.shift();
    if (a === "--json") opt.json = true;
    else if (a === "--warn-only") opt.warnOnly = true;
    else if (a === "--strict-em-dash") opt.strictEmDash = true;
    else if (a === "--em-dash-max") opt.emDashMax = Number(args.shift());
    else if (a === "--rules") opt.rules = new Set(String(args.shift()).split(",").map((s) => s.trim()).filter(Boolean));
    else if (a === "--root") opt.root = resolve(String(args.shift()));
    else if (a === "--list-rules") {
      for (const [id, r] of Object.entries(RULES)) console.log(`${id.padEnd(22)} ${r.severity.padEnd(5)} ${r.summary}`);
      return 0;
    } else if (a === "--help" || a === "-h") { console.log(readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 26).join("\n")); return 0; }
    else if (a.startsWith("--")) { console.error(`check-copy-grammar: unknown flag ${a}`); return 2; }
    else paths.push(a);
  }
  if (!paths.length) { console.error("check-copy-grammar: usage: node check-copy-grammar.mjs <path...> [--json] [--warn-only] [--rules a,b] [--em-dash-max N] [--strict-em-dash]"); return 2; }
  if (opt.rules) for (const r of opt.rules) if (!RULES[r]) { console.error(`check-copy-grammar: unknown rule ${r}`); return 2; }

  const files = [];
  for (const p of paths) walk(p, files, opt.root);
  const findings = [];
  for (const f of files) {
    let src;
    try { src = readFileSync(f, "utf8"); } catch { continue; }
    if (src.length > 2_000_000) continue; // a bundle, not copy
    for (const x of lintSource(src, f, opt)) findings.push({ ...x, file: relative(opt.root, f) || f });
  }
  const errors = findings.filter((f) => f.severity === "error");
  const warns = findings.filter((f) => f.severity === "warn");

  if (opt.json) {
    console.log(JSON.stringify({ files: files.length, errors: errors.length, warnings: warns.length, findings }, null, 2));
  } else {
    for (const f of findings) {
      const line = `${f.file}:${f.line}:${f.col} [${f.severity}] ${f.rule}: ${f.sample}`;
      console.log(line);
      if (process.env.GITHUB_ACTIONS) {
        const lvl = f.severity === "error" ? "error" : "warning";
        console.log(`::${lvl} file=${f.file},line=${f.line},col=${f.col},title=copy-grammar ${f.rule}::${f.sample} — ${RULES[f.rule].summary}`);
      }
    }
    console.log(`check-copy-grammar: ${files.length} files · ${errors.length} error(s) · ${warns.length} warning(s)`);
  }
  if (errors.length && !opt.warnOnly) return 1;
  return 0;
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) process.exit(main(process.argv.slice(2)));
