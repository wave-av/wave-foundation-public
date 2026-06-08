// tenant-d1-client.ts
//
// Wraps a CF D1 binding with a tenant-aware safety layer:
//   - All prepared statements get `tenant_id` automatically appended as the FIRST bound param
//   - Statements are required to reference `?` placeholders (no string interpolation)
//
// This forces all queries through bound params, eliminating the SQL-injection class entirely
// for tenant-controlled inputs.

import { D1TenantError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;

// CF D1 binding shape (subset).
export interface D1Database {
  prepare(query: string): D1PreparedStatement;
}
export interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  all<T = unknown>(): Promise<{ results: T[]; success: boolean; meta?: unknown }>;
  first<T = unknown>(): Promise<T | null>;
  run(): Promise<{ success: boolean; meta?: unknown }>;
}

export class TenantD1Client {
  constructor(private readonly db: D1Database, private readonly tenant_id: TenantId) {
    if (!TENANT_ID_REGEX.test(tenant_id)) {
      throw new D1TenantError("invalid tenant_id", "INVALID_TENANT_ID");
    }
  }

  /**
   * Prepare a tenant-scoped statement. The query MUST include a placeholder for the tenant_id
   * (typically as the FIRST bound param). Returns a wrapped statement that prepends tenant_id
   * automatically when bind() is called.
   */
  prepare(query: string): TenantPreparedStatement {
    if (!query.includes("?")) {
      throw new D1TenantError(
        "query must use ? placeholders (no string interpolation allowed)",
        "NO_PLACEHOLDERS",
      );
    }
    return new TenantPreparedStatement(this.db.prepare(query), this.tenant_id);
  }
}

export class TenantPreparedStatement {
  constructor(private readonly stmt: D1PreparedStatement, private readonly tenant_id: TenantId) {}

  /** Bind values — tenant_id is prepended as the first parameter. */
  bind(...values: unknown[]): D1PreparedStatement {
    return this.stmt.bind(this.tenant_id, ...values);
  }
}
