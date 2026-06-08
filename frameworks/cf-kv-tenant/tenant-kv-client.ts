// tenant-kv-client.ts
//
// Wraps a CF KV binding with a forced `<tenant_id>:` prefix on every key so even a misconfigured
// caller can't cross tenants. The wrapper is also useful when multiple tenants share a SINGLE
// namespace (cost optimization) — prefix becomes the only isolation primitive.

import { KvTenantError, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const KEY_REGEX = /^[a-zA-Z0-9_:.\-/]{1,500}$/;

// CF KV binding shape (subset).
export interface KVNamespace {
  get(key: string, options?: { type?: "text" | "json" | "arrayBuffer" | "stream" }): Promise<unknown>;
  put(key: string, value: string | ArrayBuffer | ReadableStream, options?: { expirationTtl?: number }): Promise<void>;
  delete(key: string): Promise<void>;
  list(options?: { prefix?: string; limit?: number; cursor?: string }): Promise<{
    keys: Array<{ name: string }>;
    list_complete: boolean;
    cursor?: string;
  }>;
}

export class TenantKVClient {
  constructor(private readonly ns: KVNamespace, private readonly tenant_id: TenantId) {
    if (!TENANT_ID_REGEX.test(tenant_id)) {
      throw new KvTenantError("invalid tenant_id", "INVALID_TENANT_ID");
    }
  }

  private scopedKey(key: string): string {
    if (!KEY_REGEX.test(key)) {
      throw new KvTenantError("invalid key (only alphanumeric, _, :, ., -, / allowed)", "INVALID_KEY");
    }
    return `${this.tenant_id}:${key}`;
  }

  async get(key: string, options?: { type?: "text" | "json" }): Promise<unknown> {
    return this.ns.get(this.scopedKey(key), options as any);
  }

  async put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void> {
    if (options?.expirationTtl !== undefined &&
        (!Number.isInteger(options.expirationTtl) || options.expirationTtl < 60)) {
      throw new KvTenantError("expirationTtl must be integer >= 60", "INVALID_TTL");
    }
    return this.ns.put(this.scopedKey(key), value, options);
  }

  async delete(key: string): Promise<void> {
    return this.ns.delete(this.scopedKey(key));
  }

  async list(options?: { prefix?: string; limit?: number; cursor?: string }) {
    // Force tenant prefix on every list. Caller-supplied prefix is APPENDED.
    const effective_prefix = `${this.tenant_id}:${options?.prefix ?? ""}`;
    const r = await this.ns.list({
      prefix: effective_prefix,
      limit: options?.limit,
      cursor: options?.cursor,
    });
    // Strip the tenant prefix from returned keys so callers see clean keys.
    return {
      ...r,
      keys: r.keys.map((k) => ({ name: k.name.replace(new RegExp(`^${escapeRegex(this.tenant_id)}:`), "") })),
    };
  }
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
