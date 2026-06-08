// run-due.ts
//
// Scan ALL tenants in the registry KV and fan out POSTs to target_url for crons whose
// cron_expr matches the current minute. Designed to be called from a global Worker's
// scheduled() handler, e.g. running every minute.
//
// SSRF + CREDENTIAL EXFIL DEFENSE (A21b):
//   1. target_url was already host-allowlisted at create() time (see cron-registry.ts).
//      We re-assert that invariant at fire-time as defense-in-depth — KV records could
//      have been written by another path or an older allowlist version.
//   2. Outbound requests do NOT carry a shared bearer token. Instead each call is
//      authenticated with a per-call HMAC over (tenant_id|cron_id|fired_at|payload_sha256).
//      If a record's target_url somehow lands at attacker.example, the leaked HMAC
//      is bound to that specific tenant/cron/fired_at and cannot be replayed.

import { CronError, KVLike, TenantCron } from "./types.js";
import { assertAllowedTargetUrl } from "./cron-registry.js";

export interface RunDueInput {
  kv: KVLike;
  /** Exact lowercase hostnames target_url may resolve to. Same shape used by registry. */
  allowed_dispatch_hosts: ReadonlyArray<string>;
  /** Server-only HMAC signing key (used to sign outbound calls). Min 32 bytes. */
  signing_key: string;
  /** Optional clock override. */
  at?: Date;
  /** Max concurrent fan-out fetches. */
  concurrency?: number;
}

export interface RunDueResult {
  scanned: number;
  matched: number;
  fired: number;
  failed: number;
  skipped_blocked_host: number;
  errors: Array<{ tenant_id: string; cron_id: string; status: number; reason: string }>;
}

export async function runDueTenantCrons(
  input: RunDueInput,
  fetchImpl: typeof fetch = fetch,
): Promise<RunDueResult> {
  if (!input.signing_key || input.signing_key.length < 32) {
    throw new CronError("invalid signing_key (>=32 chars)", "FETCH_FAILED");
  }
  if (!input.allowed_dispatch_hosts || input.allowed_dispatch_hosts.length === 0) {
    throw new CronError(
      "allowed_dispatch_hosts must be non-empty",
      "INVALID_TARGET_URL",
    );
  }
  const allowedHosts: ReadonlySet<string> = new Set(
    input.allowed_dispatch_hosts.map((h) => h.toLowerCase()),
  );

  const at = input.at ?? new Date();
  const firedAtIso = at.toISOString();
  const result: RunDueResult = {
    scanned: 0,
    matched: 0,
    fired: 0,
    failed: 0,
    skipped_blocked_host: 0,
    errors: [],
  };

  // Walk the entire KV (paginated). Real prod will shard, but the shape is stable.
  let cursor: string | undefined;
  const due: TenantCron[] = [];
  do {
    const page = await input.kv.list({ limit: 1000, cursor });
    for (const k of page.keys) {
      const rec = (await input.kv.get(k.name, { type: "json" })) as TenantCron | null;
      if (!rec) continue;
      result.scanned += 1;
      if (!rec.enabled) continue;
      if (!cronMatches(rec.cron_expr, at)) continue;
      // Defense-in-depth: re-assert the host allowlist at fire-time. If a record was
      // written by an older registry or another code path, this still catches it.
      try {
        assertAllowedTargetUrl(rec.target_url, allowedHosts);
      } catch {
        result.skipped_blocked_host += 1;
        result.errors.push({
          tenant_id: rec.tenant_id,
          cron_id: rec.cron_id,
          status: 0,
          reason: "blocked host",
        });
        continue;
      }
      result.matched += 1;
      due.push(rec);
    }
    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);

  // Pre-import HMAC key once for the whole tick.
  const keyBytes = new TextEncoder().encode(input.signing_key);
  const hmacKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  // Fan out with bounded concurrency.
  const concurrency = Math.max(1, Math.min(input.concurrency ?? 16, 64));
  let idx = 0;
  async function worker(): Promise<void> {
    while (idx < due.length) {
      const rec = due[idx++];
      try {
        const body = JSON.stringify({
          cron_id: rec.cron_id,
          tenant_id: rec.tenant_id,
          fired_at: firedAtIso,
          payload: rec.payload,
        });
        const payloadSha = await sha256Hex(body);
        const signedInput = `${rec.tenant_id}|${rec.cron_id}|${firedAtIso}|${payloadSha}`;
        const sigBytes = await crypto.subtle.sign(
          "HMAC",
          hmacKey,
          new TextEncoder().encode(signedInput),
        );
        const sig = bytesToBase64(new Uint8Array(sigBytes));

        const res = await fetchImpl(rec.target_url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Wave-Cron-Id": rec.cron_id,
            "X-Wave-Tenant-Id": rec.tenant_id,
            "X-Wave-Cron-Fired-At": firedAtIso,
            "X-Wave-Cron-Payload-SHA256": payloadSha,
            "X-Wave-Cron-Signature": `v1,${sig}`,
          },
          body,
        });
        if (!res.ok) {
          result.failed += 1;
          result.errors.push({
            tenant_id: rec.tenant_id,
            cron_id: rec.cron_id,
            status: res.status,
            reason: `http ${res.status}`,
          });
        } else {
          result.fired += 1;
        }
      } catch (err) {
        result.failed += 1;
        result.errors.push({
          tenant_id: rec.tenant_id,
          cron_id: rec.cron_id,
          status: 0,
          reason: err instanceof Error ? err.message : String(err),
        });
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, () => worker()));
  return result;
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

/** Match a 5-field cron expr against the given Date (UTC). */
export function cronMatches(expr: string, at: Date): boolean {
  const parts = expr.trim().split(/\s+/);
  if (parts.length !== 5) return false;
  const min = at.getUTCMinutes();
  const hr = at.getUTCHours();
  const dom = at.getUTCDate();
  const mon = at.getUTCMonth() + 1;
  const dow = at.getUTCDay();
  return (
    fieldMatch(parts[0], min, 0, 59) &&
    fieldMatch(parts[1], hr, 0, 23) &&
    fieldMatch(parts[2], dom, 1, 31) &&
    fieldMatch(parts[3], mon, 1, 12) &&
    fieldMatch(parts[4], dow, 0, 6)
  );
}

function fieldMatch(field: string, value: number, lo: number, hi: number): boolean {
  for (const tok of field.split(",")) {
    if (tok === "*") return true;
    if (tok.includes("/")) {
      const [rangeStr, stepStr] = tok.split("/");
      const step = Number(stepStr);
      if (!Number.isFinite(step) || step <= 0) continue;
      const [rLo, rHi] = parseRange(rangeStr, lo, hi);
      if (value < rLo || value > rHi) continue;
      if ((value - rLo) % step === 0) return true;
    } else if (tok.includes("-")) {
      const [a, b] = parseRange(tok, lo, hi);
      if (value >= a && value <= b) return true;
    } else {
      const n = Number(tok);
      if (Number.isFinite(n) && n === value) return true;
    }
  }
  return false;
}

function parseRange(s: string, lo: number, hi: number): [number, number] {
  if (s === "*") return [lo, hi];
  if (!s.includes("-")) {
    const n = Number(s);
    return [n, n];
  }
  const [a, b] = s.split("-").map(Number);
  return [a, b];
}
