import { describe, expect, it, vi } from "vitest";
import { provisionTenantInboundRoute } from "../provision-inbound.js";
import { verifyInboundWebhook } from "../verify-webhook.js";

function fetchOk(body: any): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: async () => body,
  } as Response) as any;
}
function fetchStatus(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: status >= 200 && status < 300,
    status,
    text: async () => "err",
    json: async () => ({}),
  } as Response) as any;
}

const validInput = {
  tenant_id: "acme",
  api_key: "re_" + "a".repeat(40),
  base_domain: "inbound.wave.online",
};

describe("provisionTenantInboundRoute", () => {
  it("happy path forces webhook URL to dispatch.wave.online/v1/inbound/<tenant>", async () => {
    let seenBody: any;
    const fetchImpl = vi.fn().mockImplementation(async (_url: string, init: any) => {
      seenBody = JSON.parse(init.body);
      return {
        ok: true,
        status: 200,
        json: async () => ({
          id: "route_abc",
          webhook_secret: "whsec_" + btoa("supersecret-bytes-for-svix-secret"),
        }),
      } as Response;
    }) as any;
    const r = await provisionTenantInboundRoute(validInput, fetchImpl);
    expect(r.webhook_url).toBe("https://dispatch.wave.online/v1/inbound/acme");
    expect(seenBody.webhook_url).toBe("https://dispatch.wave.online/v1/inbound/acme");
    expect(r.inbound_address).toBe("acme@inbound.wave.online");
  });

  it("rejects bad api_key", async () => {
    await expect(
      provisionTenantInboundRoute({ ...validInput, api_key: "abc" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_API_KEY" });
  });

  it("rejects bad base_domain", async () => {
    await expect(
      provisionTenantInboundRoute({ ...validInput, base_domain: "not a domain" }, fetchOk({})),
    ).rejects.toMatchObject({ code: "INVALID_BASE_DOMAIN" });
  });

  it("maps 401 to UNAUTHORIZED", async () => {
    await expect(
      provisionTenantInboundRoute(validInput, fetchStatus(401)),
    ).rejects.toMatchObject({ code: "UNAUTHORIZED" });
  });

  it("maps 409 to ROUTE_EXISTS", async () => {
    await expect(
      provisionTenantInboundRoute(validInput, fetchStatus(409)),
    ).rejects.toMatchObject({ code: "ROUTE_EXISTS" });
  });
});

describe("verifyInboundWebhook", () => {
  const secretRaw = "supersecret-bytes-for-svix-secret"; // ≥20 chars
  const secretB64 = btoa(secretRaw);
  const webhook_secret = `whsec_${secretB64}`;

  async function signPayload(
    msgId: string,
    timestamp: string,
    body: string,
    secret: string,
  ): Promise<string> {
    const rawSecret = secret.startsWith("whsec_") ? secret.slice("whsec_".length) : secret;
    const pad = rawSecret.length % 4 === 0 ? "" : "=".repeat(4 - (rawSecret.length % 4));
    const bin = atob(rawSecret + pad);
    const keyBytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) keyBytes[i] = bin.charCodeAt(i);
    const key = await crypto.subtle.importKey(
      "raw",
      keyBytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signed = `${msgId}.${timestamp}.${body}`;
    const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signed));
    let s = "";
    const a = new Uint8Array(sig);
    for (let i = 0; i < a.length; i++) s += String.fromCharCode(a[i]);
    return `v1,${btoa(s)}`;
  }

  const tsNow = String(Math.floor(Date.now() / 1000));
  const tsOld = String(Math.floor(Date.now() / 1000) - 10 * 60); // 10 minutes ago
  const body = JSON.stringify({
    from: "sender@example.com",
    to: ["acme@inbound.wave.online"],
    subject: "hi",
    text: "hello",
  });

  it("happy path with valid signature returns parsed InboundEmail", async () => {
    const msgId = "msg_abc";
    const sig = await signPayload(msgId, tsNow, body, webhook_secret);
    const email = await verifyInboundWebhook({
      tenant_id: "acme",
      webhook_secret,
      raw_body: body,
      svix_id: msgId,
      svix_timestamp: tsNow,
      svix_signature: sig,
    });
    expect(email.from).toBe("sender@example.com");
    expect(email.subject).toBe("hi");
  });

  it("rejects missing signature header", async () => {
    await expect(
      verifyInboundWebhook({
        tenant_id: "acme",
        webhook_secret,
        raw_body: body,
        svix_id: "msg_abc",
        svix_timestamp: tsNow,
        svix_signature: "",
      }),
    ).rejects.toMatchObject({ code: "MISSING_SIGNATURE_HEADER" });
  });

  it("rejects out-of-tolerance timestamp", async () => {
    const msgId = "msg_abc";
    const sig = await signPayload(msgId, tsOld, body, webhook_secret);
    await expect(
      verifyInboundWebhook({
        tenant_id: "acme",
        webhook_secret,
        raw_body: body,
        svix_id: msgId,
        svix_timestamp: tsOld,
        svix_signature: sig,
      }),
    ).rejects.toMatchObject({ code: "TIMESTAMP_OUT_OF_TOLERANCE" });
  });

  it("rejects tampered body (signature mismatch)", async () => {
    const msgId = "msg_abc";
    const sig = await signPayload(msgId, tsNow, body, webhook_secret);
    await expect(
      verifyInboundWebhook({
        tenant_id: "acme",
        webhook_secret,
        raw_body: body + "TAMPERED",
        svix_id: msgId,
        svix_timestamp: tsNow,
        svix_signature: sig,
      }),
    ).rejects.toMatchObject({ code: "INVALID_SIGNATURE" });
  });

  it("rejects signature with wrong secret", async () => {
    const msgId = "msg_abc";
    const otherSecret = `whsec_${btoa("different-secret-bytes-for-svix")}`;
    const sig = await signPayload(msgId, tsNow, body, otherSecret);
    await expect(
      verifyInboundWebhook({
        tenant_id: "acme",
        webhook_secret,
        raw_body: body,
        svix_id: msgId,
        svix_timestamp: tsNow,
        svix_signature: sig,
      }),
    ).rejects.toMatchObject({ code: "INVALID_SIGNATURE" });
  });

  it("accepts multiple v1 candidates (Svix multi-sig)", async () => {
    const msgId = "msg_abc";
    const goodSig = await signPayload(msgId, tsNow, body, webhook_secret);
    const fakeSig = "v1,abcdef";
    const combined = `${fakeSig} ${goodSig}`;
    const email = await verifyInboundWebhook({
      tenant_id: "acme",
      webhook_secret,
      raw_body: body,
      svix_id: msgId,
      svix_timestamp: tsNow,
      svix_signature: combined,
    });
    expect(email.tenant_id).toBe("acme");
  });
});
