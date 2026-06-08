// Canonical bucketForTenant — keep in sync with bucket-for-tenant.py.
// See README + ADR-004 in the WAVE control plane.

const POOL_PREFIX = "wave-customer-storage-pool-";
const DEFAULT_POOL_SIZE = 10;

function poolSize(): number {
  const env = typeof process !== "undefined" ? process.env?.WAVE_STORAGE_POOL_SIZE : undefined;
  const n = env ? Number.parseInt(env, 10) : DEFAULT_POOL_SIZE;
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_POOL_SIZE;
}

export async function bucketForTenant(tenantId: string): Promise<string> {
  if (!tenantId) {
    throw new Error("bucketForTenant: tenant_id required");
  }
  const data = new TextEncoder().encode(tenantId);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const index = new DataView(hash).getUint32(0, false) % poolSize();
  return `${POOL_PREFIX}${index}`;
}

export function allBucketNames(): readonly string[] {
  const n = poolSize();
  return Array.from({ length: n }, (_, i) => `${POOL_PREFIX}${i}`);
}
