import { OAuthClient } from "./oauth-client";

const CONTENT_TYPE = "application/vnd.sparebank1.v1+json; charset=utf-8";

interface TransferRequest {
  fromAccount: string;
  toAccount: string;
  amount: string;
  message: string;
  currencyCode?: string;
  dueDate?: string;
}

interface TransferResult {
  paymentId: string;
  warnings?: string[];
}

export class BankingClient {
  #oauth: OAuthClient;
  #cfg: {
    clientId: string;
    clientSecret: string;
    tokenUrl: string;
    apiBase: string;
  };

  constructor(
    cfg: {
      clientId: string;
      clientSecret: string;
      tokenUrl: string;
      apiBase: string;
    },
    tokenPath: string
  ) {
    this.#cfg = cfg;
    this.#oauth = new OAuthClient(cfg, tokenPath);
  }

  initializeTokens = (
    ...args: Parameters<OAuthClient["initializeTokens"]>
  ): Promise<void> => this.#oauth.initializeTokens(...args);

  hasTokens = (): Promise<boolean> => this.#oauth.hasTokens();

  #api = async <T>(path: string, body: object): Promise<T> => {
    const res = await this.#oauth.fetch(`${this.#cfg.apiBase}${path}`, {
      method: "POST",
      headers: { Accept: CONTENT_TYPE, "Content-Type": CONTENT_TYPE },
      body: JSON.stringify(body),
    });

    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const msg = (json as { errors?: { message: string }[] }).errors?.[0]
        ?.message;
      throw new Error(msg ?? `API error: ${res.status}`);
    }
    return json as T;
  };

  #clean = (acct: string): string => acct.replaceAll(/\s/g, "");

  getBalance = (account: string): Promise<number> =>
    this.#api<{ accountBalance: number }>(
      "/personal/banking/accounts/balance",
      {
        accountNumber: this.#clean(account),
      }
    ).then((response) => response.accountBalance);

  transfer = (req: TransferRequest): Promise<TransferResult> =>
    this.#api<TransferResult>("/personal/banking/transfer/debit", {
      ...req,
      fromAccount: this.#clean(req.fromAccount),
      toAccount: this.#clean(req.toAccount),
    });

  async executeDailyTransfer(cfg: {
    fromAccount: string;
    toAccount: string;
    message: string;
  }): Promise<{ paymentId: string; amount: number; warnings?: string[] }> {
    const balance = await this.getBalance(cfg.fromAccount);
    const now = new Date();
    const daysLeft =
      new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate() -
      now.getDate() +
      1;
    const amount = balance / daysLeft;

    if (amount <= 0) {
      throw new Error("No funds to transfer");
    }

    const result = await this.transfer({
      ...cfg,
      amount: amount.toFixed(2),
      currencyCode: "NOK",
      dueDate: now.toISOString().slice(0, 10),
    });

    return { ...result, amount };
  }
}
