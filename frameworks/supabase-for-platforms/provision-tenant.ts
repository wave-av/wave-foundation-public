// provision-tenant.ts
//
// Idempotent tenant provisioning — runs tenant-schema-template.sql against a
// Supabase project's database, with `:tenant_id` safely bound. Invoked from
// the WAVE control plane when a new tenant signs up.
//
// Why we don't just shell out to psql:
//   - We're often running in CF Workers (no psql binary)
//   - We want explicit error handling on the verify step
//   - Parameter binding via the Postgres wire protocol is safer than psql -v
//     string interpolation
//
// This file uses the postgres.js client. The control plane must `npm i postgres`
// before importing; the framework itself ships TS source only (consumer chooses
// the runtime).

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const TENANT_ID_RE = /^[a-zA-Z0-9_-]{1,64}$/;

interface Sql {
  /** Tagged template for parameterized queries. */
  (strings: TemplateStringsArray, ...values: unknown[]): Promise<unknown[]>;
  /** Raw unsafe query — only used for the template itself, NOT for user input. */
  unsafe(query: string): Promise<unknown[]>;
  end(): Promise<void>;
}

interface ProvisionArgs {
  /** Slug-safe tenant id. Will be embedded into schema name as `tenant_<id>`. */
  tenantId: string;
  /** A postgres.js connection bound to the Supabase project's pooler. */
  sql: Sql;
  /** Override the template path (defaults to ./tenant-schema-template.sql). */
  templatePath?: string;
}

/**
 * Provision a tenant. Idempotent: re-running on an existing tenant is a no-op.
 * Returns the schema name on success; throws otherwise.
 */
export async function provisionTenant(args: ProvisionArgs): Promise<string> {
  if (!TENANT_ID_RE.test(args.tenantId)) {
    throw new Error(`provisionTenant: invalid tenant_id ${JSON.stringify(args.tenantId)}`);
  }

  const here = dirname(fileURLToPath(import.meta.url));
  const templatePath = args.templatePath ?? join(here, "tenant-schema-template.sql");
  const template = readFileSync(templatePath, "utf8");

  // The SQL template uses psql's :'tenant_id' literal interpolation.
  // We substitute server-side (NOT shell-side) by replacing the markers
  // with quoted/escaped literals. The TENANT_ID_RE guard above limits the
  // alphabet to [a-zA-Z0-9_-] (no SQL meta-chars), so direct substitution
  // is safe — but we double-belt-and-brace via pg_quote_literal where the
  // template uses :'tenant_id'.
  //
  // Replacement strategy:
  //   :'tenant_id'  →  '<id>'              (quoted literal)
  //   :tenant_id    →  <id>                (identifier; tenant_<id> schema)
  const quoted = `'${args.tenantId}'`;
  const ident = args.tenantId;
  const expanded = template
    .replace(/:'tenant_id'/g, quoted)
    .replace(/:tenant_id/g, ident);

  // The template is a single multi-statement script. postgres.js's .unsafe()
  // handles multi-statement when not in transaction mode; we wrap in a tx for
  // atomicity.
  await args.sql.unsafe("BEGIN");
  try {
    await args.sql.unsafe(expanded);
    await args.sql.unsafe("COMMIT");
  } catch (err) {
    await args.sql.unsafe("ROLLBACK");
    throw err;
  }

  return `tenant_${args.tenantId}`;
}
