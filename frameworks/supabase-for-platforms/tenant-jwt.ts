// tenant-jwt.ts
//
// Issues a tenant-scoped Supabase JWT for use by CFWFP tenant scripts.
// The JWT carries `tenant_id` as a custom claim; Supabase RLS policies
// read it via current_setting('request.jwt.claims',true)::json ->> 'tenant_id'.
//
// The signing secret is Supabase's JWT_SECRET (the symmetric one Supabase
// hands to every project; rotate via the dashboard). NEVER let a tenant
// script see this secret — the JWT is minted server-side by WAVE and
// PASSED to the tenant script as a per-request env value.
//
// Algorithm: HS256 (Supabase default; matches its built-in verifier).
// Claims: { aud, exp, iat, sub, role, tenant_id }
//
// See README.md for the SQL side of the contract.

interface MintArgs {
  tenantId: string;
  /** Supabase project's JWT_SECRET (HS256 key). */
  jwtSecret: string;
  /** Token TTL in seconds. Default 60 (1 minute) — tenant scripts mint fresh
   *  for every Supabase call; long TTLs are an unnecessary blast radius. */
  ttlSeconds?: number;
  /** The Postgres role the JWT maps to. Almost always "authenticated". */
  role?: "authenticated" | "service_role";
}

const enc = new TextEncoder();

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let s = "";
  for (let i = 0; i < arr.length; i++) s += String.fromCharCode(arr[i]!);
  return btoa(s).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function base64urlJson(obj: unknown): string {
  return base64url(enc.encode(JSON.stringify(obj)));
}

const TENANT_ID_RE = /^[a-zA-Z0-9_-]{1,64}$/;

/**
 * Mint a Supabase-compatible HS256 JWT carrying the tenant_id claim.
 * Returns the encoded JWT string.
 */
export async function mintTenantJwt(args: MintArgs): Promise<string> {
  if (!TENANT_ID_RE.test(args.tenantId)) {
    throw new Error(`mintTenantJwt: invalid tenant_id ${JSON.stringify(args.tenantId)}`);
  }
  if (!args.jwtSecret) {
    throw new Error("mintTenantJwt: jwtSecret required");
  }

  const now = Math.floor(Date.now() / 1000);
  const ttl = args.ttlSeconds ?? 60;
  const role = args.role ?? "authenticated";

  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    aud: role,
    exp: now + ttl,
    iat: now,
    sub: args.tenantId,        // Supabase auth.uid() = sub when role=authenticated
    role,
    tenant_id: args.tenantId,  // ← the load-bearing claim for RLS
  };

  const signingInput = `${base64urlJson(header)}.${base64urlJson(payload)}`;
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(args.jwtSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(signingInput));
  return `${signingInput}.${base64url(sig)}`;
}
