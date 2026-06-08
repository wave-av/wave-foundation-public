// client-wrapper.ts
//
// TenantPrivyClient scopes every Privy server-API call to a specific (app_id, app_secret).
// The single guarantee: a session-token issued for tenant A's Privy app can NEVER
// authenticate against tenant B's app because basic auth is bound to (app_id, app_secret)
// at construction time.

import { PrivyError, TenantId, VerifiedPrivyUser } from "./types.js";

const PRIVY_API_BASE = "https://auth.privy.io/api/v1";
const TENANT_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;
const APP_ID_REGEX = /^[a-zA-Z0-9]{20,64}$/;
const USER_ID_REGEX = /^did:privy:[a-zA-Z0-9]+$/;

export class TenantPrivyClient {
  private readonly basicAuth: string;

  constructor(
    public readonly tenantId: TenantId,
    private readonly appId: string,
    appSecret: string,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {
    if (!TENANT_ID_REGEX.test(tenantId)) {
      throw new PrivyError("invalid tenant_id", "INVALID_TENANT_ID");
    }
    if (!APP_ID_REGEX.test(appId)) {
      throw new PrivyError("invalid app_id", "INVALID_APP_ID");
    }
    if (!appSecret || appSecret.length < 30) {
      throw new PrivyError("invalid app_secret", "INVALID_APP_SECRET");
    }
    this.basicAuth = btoa(`${appId}:${appSecret}`);
  }

  /** Look up a Privy user belonging to THIS tenant's app. */
  async getUser(userId: string): Promise<VerifiedPrivyUser> {
    if (!USER_ID_REGEX.test(userId)) {
      throw new PrivyError("invalid user_id", "INVALID_USER_ID");
    }
    const res = await this.fetchImpl(
      `${PRIVY_API_BASE}/users/${encodeURIComponent(userId)}`,
      {
        method: "GET",
        headers: this.headers(),
      },
    );

    if (res.status === 404) {
      throw new PrivyError("privy user not found", "USER_NOT_FOUND");
    }
    if (!res.ok) {
      throw new PrivyError(
        `privy getUser ${res.status}`,
        res.status === 401 ? "UNAUTHORIZED" : "API_ERROR",
      );
    }

    const body = (await res.json()) as {
      id?: string;
      linked_accounts?: Array<{ type: string; address?: string; email?: string }>;
      created_at?: number;
    };
    if (!body.id || !USER_ID_REGEX.test(body.id)) {
      throw new PrivyError("privy returned malformed user", "API_ERROR");
    }
    return {
      user_id: body.id,
      linked_accounts: body.linked_accounts ?? [],
      issued_at: body.created_at ?? Math.floor(Date.now() / 1000),
      expires_at: Math.floor(Date.now() / 1000) + 3600,
    };
  }

  /** Verify an access token issued by THIS tenant's Privy app. */
  async verifyAccessToken(token: string): Promise<VerifiedPrivyUser> {
    if (!token || token.length < 20) {
      throw new PrivyError("invalid token", "INVALID_TOKEN");
    }
    const res = await this.fetchImpl(`${PRIVY_API_BASE}/sessions/verify`, {
      method: "POST",
      headers: {
        ...this.headers(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ access_token: token }),
    });

    if (!res.ok) {
      throw new PrivyError(
        `privy verify ${res.status}`,
        res.status === 401
          ? "TOKEN_EXPIRED"
          : res.status === 403
            ? "UNAUTHORIZED"
            : "API_ERROR",
      );
    }

    const body = (await res.json()) as {
      user_id?: string;
      linked_accounts?: Array<{ type: string; address?: string; email?: string }>;
      iat?: number;
      exp?: number;
    };
    if (!body.user_id || !USER_ID_REGEX.test(body.user_id)) {
      throw new PrivyError("privy verify returned malformed user", "API_ERROR");
    }
    return {
      user_id: body.user_id,
      linked_accounts: body.linked_accounts ?? [],
      issued_at: body.iat ?? Math.floor(Date.now() / 1000),
      expires_at: body.exp ?? Math.floor(Date.now() / 1000) + 3600,
    };
  }

  private headers(): HeadersInit {
    return {
      "Authorization": `Basic ${this.basicAuth}`,
      "privy-app-id": this.appId,
    };
  }
}
