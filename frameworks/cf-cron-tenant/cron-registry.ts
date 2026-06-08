// cron-registry.ts
//
// TenantCronRegistry — KV-backed registry of tenant cron jobs.
// Keys use `<tenant_id>:<cron_id>` so a single KV namespace can hold many tenants
// without leakage on prefix-list (always scope list() by tenant prefix).
//
// SSRF/CREDENTIAL-EXFIL DEFENSE (A21b):
// target_url is allowlisted to a configured set of dispatch hostnames at create() time.
// Without this, a tenant could register https://attacker.example/exfil and the global
// cron worker would POST tenant data + a bearer token to attacker-controlled hosts.

import { CronError, KVLike, TenantCron, TenantId } from "./types.js";

const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const CRON_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const MAX_PAYLOAD_BYTES = 32 * 1024;

export interface TenantCronRegistryOptions {
  /** Exact lowercase hostnames that target_url may resolve to. */
  allowed_dispatch_hosts: ReadonlyArray<string>;
}

export class TenantCronRegistry {
  private readonly allowedHosts: ReadonlySet<string>;

  constructor(
    public readonly tenantId: TenantId,
    private readonly kv: KVLike,
    options: TenantCronRegistryOptions,
  ) {
    if (!TENANT_ID_REGEX.test(tenantId)) {
      throw new CronError("invalid tenant_id", "INVALID_TENANT_ID");
    }
    if (!options.allowed_dispatch_hosts || options.allowed_dispatch_hosts.length === 0) {
      throw new CronError(
        "allowed_dispatch_hosts must be non-empty",
        "INVALID_TARGET_URL",
      );
    }
    this.allowedHosts = new Set(options.allowed_dispatch_hosts.map((h) => h.toLowerCase()));
  }

  async create(input: {
    cron_id: string;
    cron_expr: string;
    target_url: string;
    payload: Record<string, unknown>;
    enabled?: boolean;
  }): Promise<TenantCron> {
    if (!CRON_ID_REGEX.test(input.cron_id)) {
      throw new CronError("invalid cron_id", "INVALID_CRON_ID");
    }
    if (!isValidCronExpr(input.cron_expr)) {
      throw new CronError("invalid cron_expr (need 5 fields)", "INVALID_CRON_EXPR");
    }
    assertAllowedTargetUrl(input.target_url, this.allowedHosts);

    const payload = input.payload ?? {};
    const payloadBytes = new TextEncoder().encode(JSON.stringify(payload)).byteLength;
    if (payloadBytes > MAX_PAYLOAD_BYTES) {
      throw new CronError("payload > 32KB", "PAYLOAD_TOO_LARGE");
    }
    const now = new Date().toISOString();
    const rec: TenantCron = {
      cron_id: input.cron_id,
      tenant_id: this.tenantId,
      cron_expr: input.cron_expr,
      target_url: input.target_url,
      payload,
      enabled: input.enabled ?? true,
      created_at: now,
      updated_at: now,
    };
    await this.kv.put(this.key(input.cron_id), JSON.stringify(rec));
    return rec;
  }

  async get(cron_id: string): Promise<TenantCron> {
    if (!CRON_ID_REGEX.test(cron_id)) {
      throw new CronError("invalid cron_id", "INVALID_CRON_ID");
    }
    const v = (await this.kv.get(this.key(cron_id), { type: "json" })) as TenantCron | null;
    if (!v) throw new CronError("cron not found", "NOT_FOUND");
    return v;
  }

  async setEnabled(cron_id: string, enabled: boolean): Promise<TenantCron> {
    const cur = await this.get(cron_id);
    cur.enabled = enabled;
    cur.updated_at = new Date().toISOString();
    await this.kv.put(this.key(cron_id), JSON.stringify(cur));
    return cur;
  }

  async delete(cron_id: string): Promise<void> {
    if (!CRON_ID_REGEX.test(cron_id)) {
      throw new CronError("invalid cron_id", "INVALID_CRON_ID");
    }
    await this.kv.delete(this.key(cron_id));
  }

  async list(): Promise<TenantCron[]> {
    const prefix = `${this.tenantId}:`;
    const { keys } = await this.kv.list({ prefix, limit: 1000 });
    const out: TenantCron[] = [];
    for (const k of keys) {
      const v = (await this.kv.get(k.name, { type: "json" })) as TenantCron | null;
      if (v) out.push(v);
    }
    return out;
  }

  private key(cron_id: string): string {
    return `${this.tenantId}:${cron_id}`;
  }
}

/** Conservative validator: exactly 5 whitespace-separated tokens of allowed chars. */
export function isValidCronExpr(expr: string): boolean {
  if (typeof expr !== "string") return false;
  const parts = expr.trim().split(/\s+/);
  if (parts.length !== 5) return false;
  return parts.every((p) => /^[\d*\/,\-]+$/.test(p));
}

/**
 * Throws INVALID_TARGET_URL unless target_url:
 *  - parses as a URL
 *  - has protocol https:
 *  - has hostname listed in the allowlist (exact, case-insensitive — NOT substring/suffix)
 *  - has no userinfo (https://attacker@dispatch...)
 *  - has no non-default port
 *
 * This is the primary defense against SSRF + bearer-token exfiltration via
 * tenant-supplied URLs.
 */
export function assertAllowedTargetUrl(
  target_url: string,
  allowedHosts: ReadonlySet<string>,
): void {
  let u: URL;
  try {
    u = new URL(target_url);
  } catch {
    throw new CronError("target_url not a valid URL", "INVALID_TARGET_URL");
  }
  if (u.protocol !== "https:") {
    throw new CronError("target_url must be https", "INVALID_TARGET_URL");
  }
  if (u.username || u.password) {
    throw new CronError("target_url must not carry userinfo", "INVALID_TARGET_URL");
  }
  if (u.port && u.port !== "443") {
    throw new CronError("target_url must use default https port", "INVALID_TARGET_URL");
  }
  if (!allowedHosts.has(u.hostname.toLowerCase())) {
    throw new CronError(
      `target_url hostname ${u.hostname} not in allowlist`,
      "INVALID_TARGET_URL",
    );
  }
}
