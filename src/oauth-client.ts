import { readFile, writeFile } from "node:fs/promises";

interface TokenData {
  access_token: string;
  refresh_token: string;
  expires_at: number;
}

interface OAuthConfig {
  clientId: string;
  clientSecret: string;
  tokenUrl: string;
}

export class OAuthClient {
  // eslint-disable-next-line no-unused-private-class-members
  #refreshPromise: Promise<void> | null = null;
  #config: OAuthConfig;
  #tokenPath: string;

  constructor(config: OAuthConfig, tokenPath: string) {
    this.#config = config;
    this.#tokenPath = tokenPath;
  }

  #getTokens = async (): Promise<TokenData | null> =>
    readFile(this.#tokenPath, "utf-8")
      .then((str) => JSON.parse(str) as TokenData)
      .catch(() => null);

  #saveTokens = (data: TokenData): Promise<void> =>
    writeFile(this.#tokenPath, JSON.stringify(data, null, 2));

  async initializeTokens(
    access: string,
    refresh: string,
    expiresIn: number
  ): Promise<void> {
    await this.#saveTokens({
      access_token: access,
      refresh_token: refresh,
      expires_at: Date.now() + expiresIn * 1000,
    });
  }

  hasTokens = async (): Promise<boolean> => (await this.#getTokens()) !== null;

  async fetch(input: string | URL, init?: RequestInit): Promise<Response> {
    const doFetch = async (): Promise<Response> => {
      const tokens = await this.#getTokens();
      if (!tokens) {
        throw new Error("No tokens available");
      }
      const headers = new Headers(init?.headers);
      headers.set("Authorization", `Bearer ${tokens.access_token}`);
      return fetch(input, { ...init, headers });
    };

    await this.#ensureFresh();
    const res = await doFetch();
    if (res.status === 401) {
      await this.#refresh();
      return doFetch();
    }
    return res;
  }

  #ensureFresh = async (): Promise<void> => {
    const tokens = await this.#getTokens();
    if (!tokens) {
      throw new Error("No tokens in storage");
    }
    if (tokens.expires_at - Date.now() < 60_000) {
      await this.#refresh();
    }
  };

  #refresh = async (): Promise<void> => {
    this.#refreshPromise ??= this.#doRefresh().finally(
      () => (this.#refreshPromise = null)
    );
    await this.#refreshPromise;
  };

  #doRefresh = async (): Promise<void> => {
    const tokens = await this.#getTokens();
    if (!tokens) {
      throw new Error("No refresh token");
    }

    const res = await fetch(this.#config.tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.#config.clientId,
        client_secret: this.#config.clientSecret,
        grant_type: "refresh_token",
        refresh_token: tokens.refresh_token,
      }),
    });

    if (!res.ok) {
      throw new Error(`Token refresh failed: ${res.status}`);
    }

    const data = (await res.json()) as {
      access_token: string;
      refresh_token: string;
      expires_in: number;
    };
    await this.#saveTokens({
      ...data,
      expires_at: Date.now() + data.expires_in * 1000,
    });
  };
}
