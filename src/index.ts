import { BankingClient } from "./banking-client";

const env = <T extends string[]>(...keys: T) => {
  const vals = keys.map((k) => process.env[k]);
  const missing = keys.filter((_, i) => !vals[i]);
  if (missing.length) throw new Error(`Missing env: ${missing.join(", ")}`);
  return vals as { [K in keyof T]: string };
};

const [
  CLIENT_ID,
  CLIENT_SECRET,
  TOKEN_URL,
  API_BASE,
  FROM_ACCOUNT,
  TO_ACCOUNT,
] = env(
  "CLIENT_ID",
  "CLIENT_SECRET",
  "SPAREBANK1_TOKEN_URL",
  "SPAREBANK1_API_BASE",
  "FROM_ACCOUNT",
  "TO_ACCOUNT"
);

const CONFIG = {
  fromAccount: FROM_ACCOUNT,
  toAccount: TO_ACCOUNT,
  message: "Daily budget transfer",
  runHour: 9,
} as const;

async function createClient() {
  const client = new BankingClient(
    {
      clientId: CLIENT_ID,
      clientSecret: CLIENT_SECRET,
      tokenUrl: TOKEN_URL,
      apiBase: API_BASE,
    },
    "./data/tokens.json"
  );

  if (!(await client.hasTokens())) {
    const [access, refresh] = env("ACCESS_TOKEN", "REFRESH_TOKEN");
    await client.initializeTokens(access, refresh, 600);
  }
  return client;
}

const msUntilHour = (hour: number) => {
  const now = Date.now();
  const next = new Date();
  next.setHours(hour, 0, 0, 0);
  if (next.getTime() <= now) next.setDate(next.getDate() + 1);
  return next.getTime() - now;
};

async function runTransfer(client: BankingClient) {
  const { amount, paymentId, warnings } = await client.executeDailyTransfer(
    CONFIG
  );
  console.log(`Transferred ${amount.toFixed(2)} NOK (${paymentId})`);
  if (warnings?.length) console.log(`Warnings: ${warnings.join(", ")}`);
}

const schedule = (client: BankingClient) =>
  setTimeout(async () => {
    await runTransfer(client).catch((e) => console.error(`Failed: ${e}`));
    schedule(client);
  }, msUntilHour(CONFIG.runHour));

const [, , mode] = process.argv;
if (mode === "once") await runTransfer(await createClient());
else if (mode === "schedule") schedule(await createClient());
else console.log("Usage: bun src/index.ts [once|schedule]");
