import { BankingClient } from "./banking-client";

const env = <T extends string[]>(...keys: T): { [K in keyof T]: string } => {
  const vals = keys.map((key) => process.env[key]);
  const missing = keys.filter((_, index) => !vals[index]);
  if (missing.length > 0) {
    throw new Error(`Missing env: ${missing.join(", ")}`);
  }
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

async function createClient(): Promise<BankingClient> {
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

const msUntilHour = (hour: number): number => {
  const now = Date.now();
  const next = new Date();
  next.setHours(hour, 0, 0);
  if (next.getTime() <= now) {
    next.setDate(next.getDate() + 1);
  }
  return next.getTime() - now;
};

async function runTransfer(client: BankingClient): Promise<void> {
  const { amount, paymentId, warnings } = await client.executeDailyTransfer(
    CONFIG
  );
  console.log(`Transferred ${amount.toFixed(2)} NOK (${paymentId})`);
  if (warnings && warnings.length > 0) {
    console.log(`Warnings: ${warnings.join(", ")}`);
  }
}

const schedule = (client: BankingClient): void => {
  const ms = msUntilHour(CONFIG.runHour);
  const nextRun = new Date(Date.now() + ms);
  const hours = (ms / 1000 / 60 / 60).toFixed(1);
  console.log(
    `Next transfer scheduled for ${nextRun.toISOString()} (in ${hours}h)`
  );
  setTimeout(async () => {
    await runTransfer(client).catch((error) =>
      console.error(`Failed: ${error}`)
    );
    schedule(client);
  }, ms);
};

const [_executable, _script, mode] = process.argv;
if (mode === "once") {
  await runTransfer(await createClient());
} else if (mode === "schedule") {
  console.log("Scheduler started");
  schedule(await createClient());
} else {
  console.log("Usage: bun src/index.ts [once|schedule]");
}
