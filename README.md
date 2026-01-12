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

   Fill in your SpareBank 1 OAuth credentials:

   - `CLIENT_ID`
   - `CLIENT_SECRET`
   - `SPAREBANK1_TOKEN_URL`
   - `SPAREBANK1_API_BASE`
   - `FROM_ACCOUNT` - Source account number
   - `TO_ACCOUNT` - Destination account number
   - `ACCESS_TOKEN` & `REFRESH_TOKEN` (only needed for initial setup)

3. **Run:**

   ```bash
   # Test once
   bun run src/index.ts once

   # Start daily scheduler
   bun run src/index.ts schedule
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
  banking-client.ts     # Banking API client (balance, transfers)
  index.ts              # Main scheduler & entry point
data/
  tokens.json           # Persisted tokens (gitignored)
```

### Components

- **OAuthClient**: Handles OAuth 2.0 authentication with automatic token refresh

  - Proactive refresh when within 60s of expiry
  - Retry on 401 responses
  - Concurrency-safe (single refresh at a time)
  - File-based token persistence

- **BankingClient**: Wraps SpareBank 1 API calls

  - Account balance fetching
  - Transfer execution
  - Daily transfer calculation (balance ÷ remaining days)

- **index.ts**: Main entry point
  - Environment variable validation
  - Client initialization
  - Transfer scheduling logic

## Development

### Lint

```bash
bun run lint
```

### Fix linting issues

```bash
bun run lint:fix
```

## Token Management

Token management is fully automatic:

- Proactive refresh when within 60s of expiry
- Retry on 401 responses
- Concurrency-safe (single refresh at a time)
- Tokens persisted to `data/tokens.json`

On first run, if no tokens exist, you'll need to provide `ACCESS_TOKEN` and `REFRESH_TOKEN` in your `.env` file. After that, tokens are automatically refreshed.

---

_Built with Bun v1.3.3_
