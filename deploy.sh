#!/bin/bash
# Deploy script: syncs code, rebuilds docker, restarts container

set -e

# Load deployment config from .deploy.env if it exists
if [ -f .deploy.env ]; then
  set -a
  source .deploy.env
  set +a
fi

# VPS connection details (priority: command args > env vars > .deploy.env > error)
VPS_HOST="${1:-${VPS_HOST}}"
VPS_PATH="${2:-${VPS_PATH:-~/banking}}"

# Validate VPS_HOST is set
if [ -z "$VPS_HOST" ]; then
  echo "❌ Error: VPS_HOST not set"
  echo ""
  echo "Create .deploy.env file with:"
  echo "  VPS_HOST=root@your-vps-ip"
  echo "  VPS_PATH=~/banking"
  echo ""
  echo "Or copy .deploy.env.example:"
  echo "  cp .deploy.env.example .deploy.env"
  echo "  # Then edit .deploy.env with your details"
  exit 1
fi

echo "🚀 Deploying to $VPS_HOST:$VPS_PATH"

# Create directory on VPS
ssh "$VPS_HOST" "mkdir -p $VPS_PATH/data"

# Copy all required files
echo "📦 Copying files..."
scp Dockerfile docker-compose.yml .dockerignore "$VPS_HOST:$VPS_PATH/" 2>/dev/null || true
scp package.json bun.lock tsconfig.json "$VPS_HOST:$VPS_PATH/" 2>/dev/null || true
scp -r src "$VPS_HOST:$VPS_PATH/" 2>/dev/null || true
scp env.example "$VPS_HOST:$VPS_PATH/" 2>/dev/null || true

# Copy .env if it exists (optional)
if [ -f .env ]; then
  scp .env "$VPS_HOST:$VPS_PATH/" 2>/dev/null && echo "  ✓ Copied .env" || echo "  ⚠ Failed to copy .env"
fi

# Copy tokens.json if it exists (optional)
if [ -f data/tokens.json ]; then
  ssh "$VPS_HOST" "mkdir -p $VPS_PATH/data" 2>/dev/null || true
  scp data/tokens.json "$VPS_HOST:$VPS_PATH/data/" 2>/dev/null && echo "  ✓ Copied tokens.json" || echo "  ⚠ Failed to copy tokens.json"
fi

# Rebuild and restart on VPS
echo ""
echo "🔨 Rebuilding Docker image..."
ssh "$VPS_HOST" "cd $VPS_PATH && docker compose build"

echo ""
echo "🔄 Restarting container..."
ssh "$VPS_HOST" "cd $VPS_PATH && docker compose up -d"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Container status:"
ssh "$VPS_HOST" "cd $VPS_PATH && docker compose ps"

echo ""
echo "📜 Recent logs:"
ssh "$VPS_HOST" "cd $VPS_PATH && docker compose logs --tail=10 banking"

echo ""
echo "💡 View live logs: ssh $VPS_HOST 'cd $VPS_PATH && docker compose logs -f'"
