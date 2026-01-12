import { readFile, writeFile } from "node:fs/promises";

type TokenData = {
  access_token: string;
  refresh_token: string;
  expires_at: number;
};

type OAuthConfig = {
  clientId: string;
  clientSecret: string;
  tokenUrl: string;
};

export class OAuthClient {
  private refreshPromise: Promise<void> | null = null;

  constructor(private config: OAuthConfig, private tokenPath: string) {}

  private async getTokens(): Promise<TokenData | null> {
    return readFile(this.tokenPath, "utf-8")
      .then((s) => JSON.parse(s) as TokenData)
      .catch(() => null);
  }

  private saveTokens = (data: TokenData) =>
    writeFile(this.tokenPath, JSON.stringify(data, null, 2));

  async initializeTokens(access: string, refresh: string, expiresIn: number) {
    await this.saveTokens({
      access_token: access,
      refresh_token: refresh,
      expires_at: Date.now() + expiresIn * 1000,
    });
  }

  hasTokens = async () => (await this.getTokens()) !== null;

  async fetch(input: string | URL, init?: RequestInit): Promise<Response> {
    const doFetch = async () => {
      const tokens = await this.getTokens();
      if (!tokens) throw new Error("No tokens available");
      const headers = new Headers(init?.headers);
      headers.set("Authorization", `Bearer ${tokens.access_token}`);
      return fetch(input, { ...init, headers });
    };

    await this.ensureFresh();
    const res = await doFetch();
    if (res.status === 401) {
      await this.refresh();
      return doFetch();
    }
    return res;
  }

  private async ensureFresh() {
    const tokens = await this.getTokens();
    if (!tokens) throw new Error("No tokens in storage");
    if (tokens.expires_at - Date.now() < 60_000) await this.refresh();
  }

  private async refresh() {
    this.refreshPromise ??= this.doRefresh().finally(
      () => (this.refreshPromise = null)
    );
    await this.refreshPromise;
  }

  private async doRefresh() {
    const tokens = await this.getTokens();
    if (!tokens) throw new Error("No refresh token");

    const res = await fetch(this.config.tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        grant_type: "refresh_token",
        refresh_token: tokens.refresh_token,
      }),
    });

    if (!res.ok) throw new Error(`Token refresh failed: ${res.status}`);

    const data = (await res.json()) as {
      access_token: string;
      refresh_token: string;
      expires_in: number;
    };
    await this.saveTokens({
      ...data,
      expires_at: Date.now() + data.expires_in * 1000,
    });
  }
}
