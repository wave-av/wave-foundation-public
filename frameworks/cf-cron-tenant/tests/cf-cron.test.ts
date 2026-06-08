import { describe, expect, it, vi } from "vitest";
import { TenantCronRegistry, isValidCronExpr, assertAllowedTargetUrl } from "../cron-registry.js";
import { cronMatches, runDueTenantCrons } from "../run-due.js";
import type { KVLike } from "../types.js";

const ALLOWED = ["dispatch.wave.online"] as const;
const SIGNING_KEY = "s".repeat(40);

function memKV(): KVLike & { store: Map<string, string> } {
  const store = new Map<string, string>();
  return {
    store,
    async get(key, opts) {
      const v = store.get(key);
      if (!v) return null;
      if (opts?.type === "json") return JSON.parse(v);
      return v;
    },
    async put(key, value) {
      store.set(key, value);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts) {
      const prefix = opts?.prefix ?? "";
      const limit = opts?.limit ?? 1000;
      const all = Array.from(store.keys())
        .filter((k) => k.startsWith(prefix))
        .sort();
      return {
        keys: all.slice(0, limit).map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

describe("isValidCronExpr", () => {
  it("accepts valid 5-field crons", () => {
    expect(isValidCronExpr("* * * * *")).toBe(true);
    expect(isValidCronExpr("0 9 * * *")).toBe(true);
    expect(isValidCronExpr("*/5 * * * *")).toBe(true);
    expect(isValidCronExpr("0 0,12 * * 1-5")).toBe(true);
  });
  it("rejects wrong field count", () => {
    expect(isValidCronExpr("* * * *")).toBe(false);
    expect(isValidCronExpr("* * * * * *")).toBe(false);
  });
  it("rejects illegal chars", () => {
    expect(isValidCronExpr("@daily * * * *")).toBe(false);
    expect(isValidCronExpr("a b c d e")).toBe(false);
  });
});

describe("assertAllowedTargetUrl", () => {
  const hosts = new Set(["dispatch.wave.online"]);
  it("accepts exact-match https on default port", () => {
    expect(() =>
      assertAllowedTargetUrl("https://dispatch.wave.online/v1/x", hosts),
    ).not.toThrow();
  });
  it("blocks attacker.example", () => {
    expect(() =>
      assertAllowedTargetUrl("https://attacker.example/exfil", hosts),
    ).toThrow();
  });
  it("blocks suffix-style impersonation (e.g. dispatch.wave.online.attacker.example)", () => {
    expect(() =>
      assertAllowedTargetUrl("https://dispatch.wave.online.attacker.example/x", hosts),
    ).toThrow();
  });
  it("blocks http:// (no plaintext)", () => {
    expect(() =>
      assertAllowedTargetUrl("http://dispatch.wave.online/x", hosts),
    ).toThrow();
  });
  it("blocks userinfo (https://attacker@dispatch.wave.online)", () => {
    expect(() =>
      assertAllowedTargetUrl("https://attacker@dispatch.wave.online/x", hosts),
    ).toThrow();
  });
  it("blocks non-default port", () => {
    expect(() =>
      assertAllowedTargetUrl("https://dispatch.wave.online:8443/x", hosts),
    ).toThrow();
  });
  it("is case-insensitive on hostname", () => {
    expect(() =>
      assertAllowedTargetUrl("https://DISPATCH.WAVE.ONLINE/x", hosts),
    ).not.toThrow();
  });
});

describe("TenantCronRegistry", () => {
  const opts = { allowed_dispatch_hosts: [...ALLOWED] };

  it("create + get round-trips", async () => {
    const kv = memKV();
    const r = new TenantCronRegistry("acme", kv, opts);
    const c = await r.create({
      cron_id: "daily",
      cron_expr: "0 9 * * *",
      target_url: "https://dispatch.wave.online/v1/tenant/acme/cron/daily",
      payload: { x: 1 },
    });
    expect(c.tenant_id).toBe("acme");
    const got = await r.get("daily");
    expect(got.cron_expr).toBe("0 9 * * *");
  });

  it("list scopes to tenant prefix (no cross-tenant leak)", async () => {
    const kv = memKV();
    const a = new TenantCronRegistry("acme", kv, opts);
    const b = new TenantCronRegistry("globex", kv, opts);
    await a.create({
      cron_id: "x",
      cron_expr: "* * * * *",
      target_url: "https://dispatch.wave.online/x",
      payload: {},
    });
    await b.create({
      cron_id: "y",
      cron_expr: "* * * * *",
      target_url: "https://dispatch.wave.online/y",
      payload: {},
    });
    const aList = await a.list();
    expect(aList).toHaveLength(1);
    expect(aList[0].tenant_id).toBe("acme");
  });

  it("rejects non-allowlisted target_url host (SSRF defense)", async () => {
    const kv = memKV();
    const r = new TenantCronRegistry("acme", kv, opts);
    await expect(
      r.create({
        cron_id: "x",
        cron_expr: "* * * * *",
        target_url: "https://attacker.example/exfil",
        payload: {},
      }),
    ).rejects.toMatchObject({ code: "INVALID_TARGET_URL" });
  });

  it("rejects oversized payload", async () => {
    const kv = memKV();
    const r = new TenantCronRegistry("acme", kv, opts);
    const big = "x".repeat(40 * 1024);
    await expect(
      r.create({
        cron_id: "x",
        cron_expr: "* * * * *",
        target_url: "https://dispatch.wave.online/x",
        payload: { big },
      }),
    ).rejects.toMatchObject({ code: "PAYLOAD_TOO_LARGE" });
  });

  it("constructor rejects empty allowed_dispatch_hosts", () => {
    expect(
      () => new TenantCronRegistry("acme", memKV(), { allowed_dispatch_hosts: [] }),
    ).toThrow();
  });

  it("setEnabled toggles + delete removes", async () => {
    const kv = memKV();
    const r = new TenantCronRegistry("acme", kv, opts);
    await r.create({
      cron_id: "x",
      cron_expr: "* * * * *",
      target_url: "https://dispatch.wave.online/x",
      payload: {},
    });
    await r.setEnabled("x", false);
    const got = await r.get("x");
    expect(got.enabled).toBe(false);
    await r.delete("x");
    await expect(r.get("x")).rejects.toMatchObject({ code: "NOT_FOUND" });
  });
});

describe("cronMatches", () => {
  it("matches minute-of-hour exactly", () => {
    const at = new Date(Date.UTC(2026, 5, 4, 12, 30, 0));
    expect(cronMatches("30 12 * * *", at)).toBe(true);
    expect(cronMatches("29 12 * * *", at)).toBe(false);
  });
  it("matches step expressions", () => {
    const at = new Date(Date.UTC(2026, 5, 4, 0, 10, 0));
    expect(cronMatches("*/5 * * * *", at)).toBe(true);
    const at2 = new Date(Date.UTC(2026, 5, 4, 0, 11, 0));
    expect(cronMatches("*/5 * * * *", at2)).toBe(false);
  });
  it("matches ranges + lists", () => {
    const at = new Date(Date.UTC(2026, 5, 4, 9, 0, 0)); // Thursday
    expect(cronMatches("0 9 * * 1-5", at)).toBe(true);
    expect(cronMatches("0 9 * * 0,6", at)).toBe(false);
  });
});

describe("runDueTenantCrons", () => {
  const opts = { allowed_dispatch_hosts: [...ALLOWED] };

  it("scans + fires due crons + emits HMAC signature header (no shared bearer)", async () => {
    const kv = memKV();
    const a = new TenantCronRegistry("acme", kv, opts);
    await a.create({
      cron_id: "x",
      cron_expr: "30 12 * * *",
      target_url: "https://dispatch.wave.online/x",
      payload: { k: "v" },
    });
    let seenHeaders: any = null;
    const fetchImpl = vi.fn().mockImplementation(async (_url: string, init: any) => {
      seenHeaders = init.headers;
      return { ok: true, status: 204 } as Response;
    }) as any;
    const r = await runDueTenantCrons(
      {
        kv,
        allowed_dispatch_hosts: [...ALLOWED],
        signing_key: SIGNING_KEY,
        at: new Date(Date.UTC(2026, 5, 4, 12, 30, 0)),
      },
      fetchImpl,
    );
    expect(r.matched).toBe(1);
    expect(r.fired).toBe(1);
    expect(seenHeaders["Authorization"]).toBeUndefined();
    expect(seenHeaders["X-Wave-Cron-Signature"]).toMatch(/^v1,/);
    expect(seenHeaders["X-Wave-Cron-Payload-SHA256"]).toMatch(/^[a-f0-9]{64}$/);
    expect(seenHeaders["X-Wave-Tenant-Id"]).toBe("acme");
    expect(seenHeaders["X-Wave-Cron-Fired-At"]).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it("blocks at fire-time if KV holds a non-allowlisted host (defense in depth)", async () => {
    const kv = memKV();
    // Simulate a stale/poisoned record by writing directly into KV.
    await kv.put(
      "acme:poison",
      JSON.stringify({
        cron_id: "poison",
        tenant_id: "acme",
        cron_expr: "* * * * *",
        target_url: "https://attacker.example/exfil",
        payload: {},
        enabled: true,
        created_at: "2026-06-04T00:00:00Z",
        updated_at: "2026-06-04T00:00:00Z",
      }),
    );
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 204 } as Response) as any;
    const r = await runDueTenantCrons(
      {
        kv,
        allowed_dispatch_hosts: [...ALLOWED],
        signing_key: SIGNING_KEY,
      },
      fetchImpl,
    );
    expect(r.fired).toBe(0);
    expect(r.skipped_blocked_host).toBe(1);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("skips disabled crons", async () => {
    const kv = memKV();
    const a = new TenantCronRegistry("acme", kv, opts);
    await a.create({
      cron_id: "x",
      cron_expr: "* * * * *",
      target_url: "https://dispatch.wave.online/x",
      payload: {},
    });
    await a.setEnabled("x", false);
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true, status: 204 } as Response) as any;
    const r = await runDueTenantCrons(
      { kv, allowed_dispatch_hosts: [...ALLOWED], signing_key: SIGNING_KEY },
      fetchImpl,
    );
    expect(r.matched).toBe(0);
  });

  it("records failure when target returns 500", async () => {
    const kv = memKV();
    const a = new TenantCronRegistry("acme", kv, opts);
    await a.create({
      cron_id: "x",
      cron_expr: "* * * * *",
      target_url: "https://dispatch.wave.online/x",
      payload: {},
    });
    const fetchImpl = vi.fn().mockResolvedValue({ ok: false, status: 500 } as Response) as any;
    const r = await runDueTenantCrons(
      { kv, allowed_dispatch_hosts: [...ALLOWED], signing_key: SIGNING_KEY },
      fetchImpl,
    );
    expect(r.fired).toBe(0);
    expect(r.failed).toBe(1);
    expect(r.errors[0].status).toBe(500);
  });

  it("rejects short signing_key", async () => {
    const kv = memKV();
    await expect(
      runDueTenantCrons({
        kv,
        allowed_dispatch_hosts: [...ALLOWED],
        signing_key: "short",
      }),
    ).rejects.toThrow();
  });

  it("HMAC differs per tenant even with identical cron_id + fired_at (replay binding)", async () => {
    const kv = memKV();
    const a = new TenantCronRegistry("acme", kv, opts);
    const b = new TenantCronRegistry("globex", kv, opts);
    await a.create({
      cron_id: "x",
      cron_expr: "* * * * *",
      target_url: "https://dispatch.wave.online/x",
      payload: {},
    });
    await b.create({
      cron_id: "x",
      cron_expr: "* * * * *",
      target_url: "https://dispatch.wave.online/x",
      payload: {},
    });
    const sigs: Record<string, string> = {};
    const fetchImpl = vi.fn().mockImplementation(async (_url: string, init: any) => {
      const tenant = init.headers["X-Wave-Tenant-Id"];
      sigs[tenant] = init.headers["X-Wave-Cron-Signature"];
      return { ok: true, status: 204 } as Response;
    }) as any;
    await runDueTenantCrons(
      {
        kv,
        allowed_dispatch_hosts: [...ALLOWED],
        signing_key: SIGNING_KEY,
        at: new Date(Date.UTC(2026, 5, 4, 0, 0, 0)),
      },
      fetchImpl,
    );
    expect(sigs.acme).toBeDefined();
    expect(sigs.globex).toBeDefined();
    expect(sigs.acme).not.toBe(sigs.globex);
  });
});
