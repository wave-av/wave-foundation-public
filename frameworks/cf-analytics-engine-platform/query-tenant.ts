// query-tenant.ts
//
// Tenant-scoped SQL query helper for CF Analytics Engine.
// Forces a WHERE clause on index1 = tenant_id so a misuse can't leak across tenants.
//
// SECURITY NOTES (A5b hardening):
//   - All clause inputs (select/where/group/order) pass a TIGHT character allowlist that EXCLUDES
//     quotes, semicolons, comment markers (--, /*, */), and dangerous SQL keywords (FROM/JOIN/
//     UNION/SELECT/WITH/INSERT/UPDATE/DELETE/DROP/ALTER/CREATE/TRUNCATE/REPLACE/EXEC). Anchored.
//   - since_iso must match a STRICT ISO-8601 shape, anchored at both ends, no quote chars allowed.
//   - tenant_id interpolation single-quote-escapes (defense-in-depth; the tenant_id regex already
//     blocks quotes, but escape unconditionally).
//
// CF AE SQL API:
//   POST https://api.cloudflare.com/client/v4/accounts/{account_id}/analytics_engine/sql

import { AnalyticsEngineError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const DATASET_REGEX = /^[a-zA-Z][a-zA-Z0-9_]{0,63}$/;

// Anchored token-list allowlist. Allowed:
//   identifiers, digits, underscore, dot, comma, parens, asterisk, basic arithmetic + comparisons,
//   spaces. NO quotes, NO semicolons, NO backticks, NO comment markers.
// We then re-scan for keywords that would change query shape.
const SAFE_CLAUSE_REGEX = /^[a-zA-Z0-9_(),.\s+\-*/=<>!]+$/;

// Strict ISO-8601 UTC. Anchored. No quote chars by construction (regex doesn't allow them).
const STRICT_ISO_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z?$/;

const FORBIDDEN_KEYWORDS = [
  "FROM", "JOIN", "UNION", "SELECT", "WITH",
  "INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE",
  "TRUNCATE", "REPLACE", "EXEC", "EXECUTE",
];
const FORBIDDEN_SEQUENCES = ["--", "/*", "*/", ";", "'", '"', "`", "\\"];

function assertSafeClause(name: string, value: string, code: string): void {
  if (!SAFE_CLAUSE_REGEX.test(value)) {
    throw new AnalyticsEngineError(`${name} contains disallowed characters`, code);
  }
  for (const seq of FORBIDDEN_SEQUENCES) {
    if (value.includes(seq)) {
      throw new AnalyticsEngineError(`${name} contains forbidden sequence ${seq}`, code);
    }
  }
  // Case-insensitive keyword scan on whole-word boundaries.
  const upper = value.toUpperCase();
  for (const kw of FORBIDDEN_KEYWORDS) {
    const re = new RegExp(`\\b${kw}\\b`, "i");
    if (re.test(upper)) {
      throw new AnalyticsEngineError(`${name} contains forbidden keyword ${kw}`, code);
    }
  }
}

export interface QueryInput {
  account_id: string;
  api_token: string;
  tenant_id: TenantId;
  dataset: string;
  /** SELECT clause body, e.g. "blob1, count() AS c". No quotes, no keywords, no semicolons. */
  select_clause: string;
  /** Optional extra WHERE conditions (ANDed with tenant filter). */
  where_extra?: string;
  /** Optional GROUP BY clause. */
  group_by?: string;
  /** Optional ORDER BY clause. */
  order_by?: string;
  limit?: number;
  /** Optional time range, STRICT ISO-8601 (e.g. 2026-06-01T00:00:00Z). */
  since_iso?: string;
}

export interface QueryResult {
  rows: Record<string, unknown>[];
  meta: { tenant_id: TenantId; dataset: string; query: string };
}

export async function queryTenantAnalytics(
  input: QueryInput,
  fetchImpl: typeof fetch = fetch,
): Promise<QueryResult> {
  if (!TENANT_ID_REGEX.test(input.tenant_id)) {
    throw new AnalyticsEngineError("invalid tenant_id", "INVALID_TENANT_ID");
  }
  if (!DATASET_REGEX.test(input.dataset)) {
    throw new AnalyticsEngineError("invalid dataset name", "INVALID_DATASET");
  }
  assertSafeClause("select_clause", input.select_clause, "INVALID_SELECT");
  if (input.limit !== undefined && (!Number.isInteger(input.limit) || input.limit < 1 || input.limit > 10000)) {
    throw new AnalyticsEngineError("limit must be integer in [1, 10000]", "INVALID_LIMIT");
  }

  // Build tenant filter. Defense-in-depth: single-quote escape even though TENANT_ID_REGEX
  // already blocks quotes.
  const conditions = [
    `index1 = '${input.tenant_id.replace(/'/g, "''")}'`,
  ];
  if (input.where_extra) {
    assertSafeClause("where_extra", input.where_extra, "INVALID_WHERE");
    conditions.push(`(${input.where_extra})`);
  }
  if (input.since_iso) {
    if (!STRICT_ISO_REGEX.test(input.since_iso)) {
      throw new AnalyticsEngineError("invalid since_iso (must be strict ISO-8601 UTC)", "INVALID_SINCE");
    }
    conditions.push(`timestamp >= toDateTime('${input.since_iso}')`);
  }

  let query = `SELECT ${input.select_clause} FROM ${input.dataset} WHERE ${conditions.join(" AND ")}`;
  if (input.group_by) {
    assertSafeClause("group_by", input.group_by, "INVALID_GROUP_BY");
    query += ` GROUP BY ${input.group_by}`;
  }
  if (input.order_by) {
    assertSafeClause("order_by", input.order_by, "INVALID_ORDER_BY");
    query += ` ORDER BY ${input.order_by}`;
  }
  if (input.limit !== undefined) {
    query += ` LIMIT ${input.limit}`;
  }

  let res: Response;
  try {
    res = await fetchImpl(
      `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(input.account_id)}/analytics_engine/sql`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${input.api_token}`,
          "Content-Type": "text/plain",
        },
        body: query,
      },
    );
  } catch (err) {
    throw new AnalyticsEngineError("cf ae fetch failed", "FETCH_FAILED", err);
  }

  if (!res.ok) {
    throw new AnalyticsEngineError(`cf ae query ${res.status}`, "QUERY_FAILED");
  }

  const body = (await res.json()) as { data?: Record<string, unknown>[] };
  return {
    rows: body.data ?? [],
    meta: { tenant_id: input.tenant_id, dataset: input.dataset, query },
  };
}
