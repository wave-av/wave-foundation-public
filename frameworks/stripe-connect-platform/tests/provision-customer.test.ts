import { describe, expect, it, vi } from "vitest";
import { provisionCustomerStripeAccount } from "../provision-customer.js";
import { StripeConnectError } from "../types.js";

function mockStripe(overrides: Partial<Record<string, any>> = {}) {
  return {
    accounts: {
      create: vi.fn().mockResolvedValue({ id: "acct_test123", ...overrides.account }),
    },
    accountLinks: {
      create: vi.fn().mockResolvedValue({
        url: "https://connect.stripe.com/setup/test",
        ...overrides.accountLink,
      }),
    },
    webhookEndpoints: {
      create: vi.fn().mockResolvedValue({ id: "we_test456", ...overrides.webhook }),
    },
  } as any;
}

const validInput = {
  tenant_id: "acme",
  email: "owner@acme.example",
  return_url: "https://wave.online/onboarding/return",
  refresh_url: "https://wave.online/onboarding/refresh",
  webhook_url: "https://api.wave.online/v1/stripe/webhook/acme",
  country: "US",
} as const;

describe("provisionCustomerStripeAccount", () => {
  it("happy path returns ProvisionedAccount with all IDs populated", async () => {
    const stripe = mockStripe();
    const result = await provisionCustomerStripeAccount(stripe, validInput);

    expect(result.tenant_id).toBe("acme");
    expect(result.stripe_account_id).toBe("acct_test123");
    expect(result.onboarding_url).toBe("https://connect.stripe.com/setup/test");
    expect(result.webhook_endpoint_id).toBe("we_test456");
    expect(result.created_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);

    expect(stripe.accounts.create).toHaveBeenCalledWith(
      expect.objectContaining({
        type: "express",
        email: "owner@acme.example",
        metadata: { wave_tenant_id: "acme" },
      }),
    );
  });

  it("rejects invalid tenant_id (path traversal etc.)", async () => {
    const stripe = mockStripe();
    await expect(
      provisionCustomerStripeAccount(stripe, { ...validInput, tenant_id: "../etc/passwd" }),
    ).rejects.toMatchObject({ name: "StripeConnectError", code: "INVALID_TENANT_ID" });
    expect(stripe.accounts.create).not.toHaveBeenCalled();
  });

  it("rejects empty tenant_id", async () => {
    const stripe = mockStripe();
    await expect(
      provisionCustomerStripeAccount(stripe, { ...validInput, tenant_id: "" }),
    ).rejects.toMatchObject({ code: "INVALID_TENANT_ID" });
  });

  it("rejects non-HTTPS webhook_url", async () => {
    const stripe = mockStripe();
    await expect(
      provisionCustomerStripeAccount(stripe, {
        ...validInput,
        webhook_url: "http://api.wave.online/v1/stripe/webhook/acme",
      }),
    ).rejects.toMatchObject({ code: "INVALID_URL" });
  });

  it("rejects invalid email", async () => {
    const stripe = mockStripe();
    await expect(
      provisionCustomerStripeAccount(stripe, { ...validInput, email: "not-an-email" }),
    ).rejects.toMatchObject({ code: "INVALID_EMAIL" });
  });

  it("wraps stripe.accounts.create failure in StripeConnectError", async () => {
    const stripe = mockStripe();
    stripe.accounts.create.mockRejectedValueOnce(new Error("rate_limited"));
    await expect(provisionCustomerStripeAccount(stripe, validInput)).rejects.toMatchObject({
      name: "StripeConnectError",
      code: "ACCOUNT_CREATE_FAILED",
    });
  });

  it("wraps stripe.webhookEndpoints.create failure in StripeConnectError", async () => {
    const stripe = mockStripe();
    stripe.webhookEndpoints.create.mockRejectedValueOnce(new Error("conflict"));
    await expect(provisionCustomerStripeAccount(stripe, validInput)).rejects.toMatchObject({
      name: "StripeConnectError",
      code: "WEBHOOK_CREATE_FAILED",
    });
  });

  it("forwards country prefill when provided", async () => {
    const stripe = mockStripe();
    await provisionCustomerStripeAccount(stripe, { ...validInput, country: "GB" });
    expect(stripe.accounts.create).toHaveBeenCalledWith(
      expect.objectContaining({ country: "GB" }),
    );
  });
});
