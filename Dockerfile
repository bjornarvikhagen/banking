FROM oven/bun:1 AS base
WORKDIR /app

# Install dependencies
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

# Copy source code
COPY tsconfig.json ./
COPY src ./src

# Create data directory for token persistence
RUN mkdir -p /app/data

# Default to schedule mode
CMD ["bun", "run", "src/index.ts", "schedule"]
