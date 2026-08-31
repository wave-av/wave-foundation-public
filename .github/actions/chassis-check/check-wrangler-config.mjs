#!/usr/bin/env node
/**
 * check-wrangler-config.mjs — detect the "routes silently nested under a TOML
 * table header" landmine that caused two full deploy cycles to be wasted.
 *
 * WHY THIS EXISTS
 * ---------------
 * wrangler.toml: `routes = [...]` or `custom_domain = true` placed AFTER any
 * `[section]` header (e.g. `[observability]`) is parsed by TOML as a subkey of
 * that section (e.g. `observability.routes`) and SILENTLY IGNORED — wrangler
 * emits "Unexpected fields found in observability field: routes" but still exits
 * 0. The custom domain never attaches. This hit two product workers in the
 * same session before anything caught it. See config-no-silent-noop.md.
 *
 * RULE
 * ----
 * In wrangler.toml, `routes` and `custom_domain` keys MUST appear BEFORE the
 * first `[table]` header. After any `[section]`, they are unreachable top-level.
 *
 * For wrangler.jsonc / wrangler.json, the JSON format has no ordering trap (any
 * top-level key is genuinely top-level), but we still verify the key exists if
 * one is expected (pass --require-routes or --require-custom-domain to enforce).
 *
 * CONTRACT
 * --------
 * Auto-discovers wrangler.toml / wrangler.jsonc / wrangler.json in CWD, or
 * accepts an explicit path argument.
 *
 * Exit 0 = pass; exit 1 = fail (noop trap detected); exit 2 = usage error.
 *
 * Node 22, stdlib only.
 */

import { readFileSync, existsSync } from "node:fs";
import { resolve, extname } from "node:path";

// ─── TOML LINE SCANNER ────────────────────────────────────────────────────────
// We do NOT need full TOML parsing — only positional ordering matters. We scan
// lines looking for:
//   a) a `[table]` header (simple [word] or [[array-of-tables]])
//   b) a top-level key assignment for `routes` or `custom_domain`
//
// Key rule: once we have seen a `[table]` header, any `routes` or
// `custom_domain` key that follows is silently nested into that table, NOT
// top-level. Wrangler silently ignores it.

const TOP_LEVEL_KEY_RE = /^\s*(routes|custom_domain)\s*=/;
const TABLE_HEADER_RE = /^\s*\[\[?[a-zA-Z0-9_.-]/;
// Lines that are comments or blank — safe to skip.
const BLANK_OR_COMMENT_RE = /^\s*(#.*)?$/;

/**
 * @param {string} tomlText
 * @param {string} filePath  (for error messages)
 * @returns {{ violations: string[], warnings: string[] }}
 */
function checkToml(tomlText, filePath) {
  const lines = tomlText.split("\n");
  const violations = [];
  const warnings = [];
  let firstTableLine = -1;
  let currentTable = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNo = i + 1;

    if (BLANK_OR_COMMENT_RE.test(line)) continue;

    if (TABLE_HEADER_RE.test(line)) {
      if (firstTableLine === -1) firstTableLine = lineNo;
      // Extract table name for context
      const m = line.match(/^\s*\[+([^\]]+)/);
      currentTable = m ? m[1].trim() : "?";
      continue;
    }

    if (TOP_LEVEL_KEY_RE.test(line)) {
      const keyM = line.match(/^\s*(routes|custom_domain)\s*=/);
      const key = keyM ? keyM[1] : "?";
      if (firstTableLine !== -1) {
        violations.push(
          `Line ${lineNo}: \`${key}\` appears after \`[${currentTable}]\` (first table at line ${firstTableLine}).\n` +
          `  In TOML, this key becomes \`${currentTable}.${key}\` — a SUBKEY, not top-level.\n` +
          `  wrangler silently ignores it ("Unexpected fields found in ${currentTable} field: ${key}").\n` +
          `  Fix: move \`${key} = ...\` above the first \`[section]\` header.\n` +
          `  See config-no-silent-noop.md — wrangler.toml routes-placement trap.`
        );
      }
    }
  }

  return { violations, warnings };
}

// ─── JSONC CHECK ─────────────────────────────────────────────────────────────
// JSON/JSONC has no ordering trap — any top-level key is genuinely top-level.
// We still parse and report whether routes/custom_domain exist.

function stripJsonComments(text) {
  // Remove block comments
  text = text.replace(/\/\*[\s\S]*?\*\//g, "");
  // Remove line comments (but not URLs)
  text = text.replace(/(^|[^:])\/\/[^\n]*/g, "$1");
  // Remove trailing commas
  text = text.replace(/,(\s*[}\]])/g, "$1");
  return text;
}

function checkJsonc(jsoncText, filePath) {
  const violations = [];
  const warnings = [];
  let parsed;
  try {
    parsed = JSON.parse(stripJsonComments(jsoncText));
  } catch (e) {
    violations.push(`Cannot parse ${filePath} as JSONC: ${e.message}`);
    return { violations, warnings };
  }

  // JSON has no ordering trap — just note what's present for transparency.
  const hasRoutes = "routes" in parsed;
  const hasCustomDomain =
    "custom_domain" in parsed ||
    (Array.isArray(parsed.routes) && parsed.routes.some((r) => r && r.custom_domain));

  if (!hasRoutes && !hasCustomDomain) {
    warnings.push(
      `${filePath}: no top-level \`routes\` or \`custom_domain\` found.\n` +
      `  (Not a failure — JSON has no ordering trap. Add --require-routes to enforce presence.)`
    );
  } else {
    const keys = [hasRoutes && "routes", hasCustomDomain && "custom_domain"].filter(Boolean);
    warnings.push(`${filePath}: JSON format — ${keys.join(", ")} present at top level (no ordering trap).`);
  }

  return { violations, warnings };
}

// ─── FILE DISCOVERY ───────────────────────────────────────────────────────────

function discoverConfig(explicitPath) {
  if (explicitPath) {
    if (!existsSync(explicitPath)) {
      console.error(`check-wrangler-config: file not found: ${explicitPath}`);
      process.exit(2);
    }
    return explicitPath;
  }
  for (const name of ["wrangler.toml", "wrangler.jsonc", "wrangler.json"]) {
    if (existsSync(name)) return name;
  }
  return null;
}

// ─── ENTRYPOINT ───────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
// Filter out flags we don't use yet (reserved for future --require-routes etc.)
const paths = args.filter((a) => !a.startsWith("--"));
const filePaths = paths.length > 0 ? paths : [discoverConfig(null)].filter(Boolean);

if (filePaths.length === 0) {
  console.log(
    "check-wrangler-config: no wrangler config found (looked for wrangler.toml/.jsonc/.json in CWD). Nothing to check."
  );
  process.exit(0);
}

let anyViolation = false;

for (const rawPath of filePaths) {
  const filePath = resolve(rawPath);
  let text;
  try {
    text = readFileSync(filePath, "utf8");
  } catch (e) {
    console.error(`check-wrangler-config: cannot read ${filePath}: ${e.message}`);
    anyViolation = true;
    continue;
  }

  const ext = extname(filePath);
  const { violations, warnings } = ext === ".toml"
    ? checkToml(text, filePath)
    : checkJsonc(text, filePath);

  for (const w of warnings) console.log(`check-wrangler-config: ⚠  ${w}`);
  for (const v of violations) {
    console.error(`check-wrangler-config: ✗ ${v}`);
    anyViolation = true;
  }

  if (violations.length === 0) {
    const label = ext === ".toml" ? "TOML ordering" : "JSON format (no ordering trap)";
    console.log(`check-wrangler-config: ✓ ${filePath} — ${label} check passed.`);
  }
}

process.exit(anyViolation ? 1 : 0);
