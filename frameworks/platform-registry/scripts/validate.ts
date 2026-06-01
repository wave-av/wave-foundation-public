#!/usr/bin/env tsx
/**
 * Validate a capabilities.json file against the schema.
 *
 * Invoked by every consumer repo's CI as part of _checks.yml. Exit 0 = valid,
 * exit 1 = schema violation (with a human-readable diff). No deps — uses
 * Node's built-in JSON parser + a tiny hand-written validator that matches
 * the limited shape of our schema (avoids pulling in ajv just for this).
 *
 * Usage:
 *   tsx validate.ts capabilities.json
 */

import { promises as fs } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const target = process.argv[2];
if (!target) {
  console.error('usage: tsx validate.ts <capabilities.json>');
  process.exit(2);
}

const here = dirname(fileURLToPath(import.meta.url));
const schemaPath = join(here, '..', 'schema', 'capabilities.schema.json');

interface Schema {
  required?: string[];
  properties?: Record<string, { type?: string | string[]; enum?: unknown[]; pattern?: string; const?: unknown }>;
}

async function main(): Promise<void> {
  const schemaRaw = await fs.readFile(schemaPath, 'utf8');
  const fileRaw = await fs.readFile(target!, 'utf8');
  const schema = JSON.parse(schemaRaw) as Schema;
  let value: Record<string, unknown>;
  try {
    value = JSON.parse(fileRaw) as Record<string, unknown>;
  } catch (err) {
    console.error(`capabilities.json is not valid JSON: ${err instanceof Error ? err.message : err}`);
    process.exit(1);
  }

  const errors: string[] = [];

  // Required top-level fields.
  for (const req of schema.required ?? []) {
    if (!(req in value)) errors.push(`missing required field: ${req}`);
  }

  // Type checks on the fields we care most about (rest is permissive).
  const properties = schema.properties ?? {};
  for (const [key, def] of Object.entries(properties)) {
    if (!(key in value)) continue;
    const got = value[key];
    if (def.const !== undefined && got !== def.const) {
      errors.push(`${key}: expected const ${JSON.stringify(def.const)}, got ${JSON.stringify(got)}`);
    }
    if (def.enum && !def.enum.includes(got as never)) {
      errors.push(`${key}: not one of ${def.enum.join(', ')} — got ${JSON.stringify(got)}`);
    }
    if (def.pattern && typeof got === 'string' && !new RegExp(def.pattern).test(got)) {
      errors.push(`${key}: does not match pattern ${def.pattern}`);
    }
  }

  if (errors.length > 0) {
    console.error('capabilities.json failed validation:');
    for (const e of errors) console.error(`  - ${e}`);
    process.exit(1);
  }
  console.log('capabilities.json: valid');
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
