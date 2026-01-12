#!/usr/bin/env bash
# ultra-deploy.sh — deterministic, loud, and mildly paranoid

set -Eeuo pipefail
IFS=$'\n\t'

#######################################
# Styling
#######################################
if [[ -t 1 ]]; then
  BOLD=$(tput bold)
  DIM=$(tput dim)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  RESET=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

log()   { echo -e "${BLUE}▸${RESET} $*"; }
ok()    { echo -e "${GREEN}✓${RESET} $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $*"; }
die()   { echo -e "${RED}✖${RESET} $*" >&2; exit 1; }

trap 'die "failed at line $LINENO"' ERR

#######################################
# Load config (.deploy.env)
#######################################
if [[ -f .deploy.env ]]; then
  while IFS='=' read -r k v; do
    [[ -z "$k" || "$k" =~ ^# ]] && continue
    case "$k" in
      VPS_HOST|VPS_PATH) export "$k=$v" ;;
    esac
  done < .deploy.env
fi

#######################################
# Args > env > defaults
#######################################
VPS_HOST="${1:-${VPS_HOST:-}}"
VPS_PATH="${2:-${VPS_PATH:-~/banking}}"

[[ -z "$VPS_HOST" ]] && die "VPS_HOST unset (arg, env, or .deploy.env)"

#######################################
# Preflight
#######################################
command -v rsync >/dev/null || die "rsync missing"
command -v ssh   >/dev/null || die "ssh missing"

log "Deploy target: ${BOLD}$VPS_HOST:$VPS_PATH${RESET}"

#######################################
# Remote prep (single SSH)
#######################################
log "Preparing remote directories"
ssh "$VPS_HOST" "mkdir -p $VPS_PATH/data" >/dev/null
ok "Remote ready"

#######################################
# Rsync payload
#######################################
log "Syncing filesystem delta"

rsync -az --delete \
  --exclude={node_modules,.git,data,.env,.deploy.env,*.log,.DS_Store} \
  ./ "$VPS_HOST:$VPS_PATH/"

ok "Code synced"

#######################################
# Secrets & mutable state
#######################################
if [[ -f .env ]]; then
  rsync -az .env "$VPS_HOST:$VPS_PATH/" && ok ".env synced"
else
  warn ".env missing (skipped)"
fi

if [[ -f data/tokens.json ]]; then
  rsync -az data/tokens.json "$VPS_HOST:$VPS_PATH/data/" && ok "tokens.json synced"
fi

#######################################
# Build + restart (single SSH session)
#######################################
log "Rebuilding & restarting containers"

ssh "$VPS_HOST" <<EOF
  set -e
  cd $VPS_PATH
  docker compose -f docker-compose.yml build
  docker compose -f docker-compose.yml up -d
EOF

ok "Containers live"

#######################################
# Postflight
#######################################
echo
log "Container status"
ssh "$VPS_HOST" "cd $VPS_PATH && docker compose -f docker-compose.yml ps"

echo
log "Recent logs"
ssh "$VPS_HOST" "cd $VPS_PATH && docker compose -f docker-compose.yml logs --tail=10 banking"

echo
ok "Deployment complete"
echo "${DIM}Live logs:${RESET} ssh $VPS_HOST \"cd $VPS_PATH && docker compose -f docker-compose.yml logs -f\""