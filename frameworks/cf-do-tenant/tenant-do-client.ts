// tenant-do-client.ts
//
// Safe DO client that derives the DO id from (tenant_id, logical_name) using SHA-256.
// Two tenants requesting the same logical_name get DIFFERENT DO instances by construction.
//
// Without this wrapper, callers might do `binding.idFromName(logical_name)` which is
// tenant-collision-prone: two tenants both asking for "session-default" hit the same DO.

import { DoTenantError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const LOGICAL_NAME_REGEX = /^[a-zA-Z0-9_:.\-]{1,200}$/;

// CF Workers DurableObjectNamespace shape (subset).
export interface DurableObjectNamespace {
  idFromName(name: string): DurableObjectId;
  newUniqueId(): DurableObjectId;
  get(id: DurableObjectId): DurableObjectStub;
}
export interface DurableObjectId {
  toString(): string;
}
export interface DurableObjectStub {
  fetch(request: Request | string, init?: RequestInit): Promise<Response>;
}

export class TenantDOClient {
  constructor(
    private readonly ns: DurableObjectNamespace,
    private readonly tenant_id: TenantId,
  ) {
    if (!TENANT_ID_REGEX.test(tenant_id)) {
      throw new DoTenantError("invalid tenant_id", "INVALID_TENANT_ID");
    }
  }

  /**
   * Get a DO stub for (tenant_id, logical_name). The DO name is `<tenant_id>:<logical_name>`
   * (CF will hash to a stable id), so two tenants never collide on the same logical_name.
   */
  for(logical_name: string): DurableObjectStub {
    if (!LOGICAL_NAME_REGEX.test(logical_name)) {
      throw new DoTenantError("invalid logical_name", "INVALID_LOGICAL_NAME");
    }
    const scoped = `${this.tenant_id}:${logical_name}`;
    return this.ns.get(this.ns.idFromName(scoped));
  }

  /** Generate a fresh per-call ephemeral DO scoped to the tenant. */
  ephemeral(): DurableObjectStub {
    return this.ns.get(this.ns.newUniqueId());
  }
}
