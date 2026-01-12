# banking

Daily budget transfer bot for SpareBank 1.

## What It Does

Every day at 09:00, the bot:

1. Fetches the balance from your source account
2. Calculates: `balance ÷ remaining days in month`
3. Transfers that amount to your destination account

This spreads your monthly budget evenly across the remaining days.

## Setup

1. **Install:**

   ```bash
   bun install
   ```

2. **Configure `.env`:**

   ```bash
   cp env.example .env
   ```

   Fill in your SpareBank 1 OAuth credentials.

3. **Edit account numbers in `src/index.ts`:**
   ```typescript
   const FROM_ACCOUNT = "42125167564"; // Your source account
   const TO_ACCOUNT = "42145570276"; // Your destination account
   ```

## Usage

### Test once

```bash
bun run src/index.ts once
```

### Run daily scheduler

```bash
bun run src/index.ts schedule
```

## Example

If on January 15th your account has 15,000 NOK and there are 17 days left in the month:

- Transfer amount: `15,000 ÷ 17 = 882.35 NOK`

Next day (16th) with 14,118.65 NOK remaining and 16 days left:

- Transfer amount: `14,118.65 ÷ 16 = 882.42 NOK`

And so on until the last day of the month.

## Architecture

```
src/
  oauth-client.ts       # OAuth 2.0 with auto-refresh
  file-token-storage.ts # Token persistence
  accounts.ts           # Get account balance
  transfers.ts          # Create transfers
  date-utils.ts         # Calculate remaining days
  index.ts              # Main scheduler
data/
  tokens.json           # Persisted tokens (gitignored)
```

Token management is fully automatic:

- Proactive refresh when within 60s of expiry
- Retry on 401 responses
- Concurrency-safe (single refresh at a time)

---

_Built with Bun v1.3.3_
