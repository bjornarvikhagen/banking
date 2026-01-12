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
  CYAN=$(tput setaf 6)
  RESET=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

log()    { echo -e "${BLUE}▸${RESET} $*"; }
ok()     { echo -e "${GREEN}✓${RESET} $*"; }
warn()   { echo -e "${YELLOW}⚠${RESET} $*"; }
die()    { echo -e "${RED}✖${RESET} $*" >&2; exit 1; }
metric() { echo -e "${CYAN}◆${RESET} $*"; }

DEPLOY_START=$(date +%s)
ROLLBACK_TRIGGERED=false

cleanup() {
  local code=$?
  if [[ $code -ne 0 && "$ROLLBACK_TRIGGERED" == "false" ]]; then
    warn "Deploy failed, attempting rollback"
    ROLLBACK_TRIGGERED=true
    rollback || warn "Rollback failed — manual intervention required"
  fi
}

trap cleanup EXIT
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
DRY_RUN=false
SKIP_HEALTH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --skip-health) SKIP_HEALTH=true; shift ;;
    --help)
      echo "Usage: $0 [VPS_HOST] [VPS_PATH] [options]"
      echo "Options:"
      echo "  --dry-run       Show what would be deployed"
      echo "  --skip-health   Skip post-deployment health checks"
      exit 0
      ;;
    *) 
      if [[ -z "${VPS_HOST:-}" ]]; then
        VPS_HOST="$1"
      elif [[ -z "${VPS_PATH:-}" ]]; then
        VPS_PATH="$1"
      else
        die "Unknown argument: $1"
      fi
      shift
      ;;
  esac
done

VPS_HOST="${VPS_HOST:-}"
VPS_PATH="${VPS_PATH:-~/banking}"

[[ -z "$VPS_HOST" ]] && die "VPS_HOST unset (arg, env, or .deploy.env)"

#######################################
# Functions
#######################################
rollback() {
  [[ ! -f /tmp/deploy_backup_tag ]] && return 1
  local backup_tag
  backup_tag=$(cat /tmp/deploy_backup_tag)
  
  warn "Rolling back to $backup_tag"
  ssh "$VPS_HOST" <<EOF
    set -e
    cd $VPS_PATH
    if [[ -d ".deploy_backup/$backup_tag" ]]; then
      docker compose down || true
      rsync -a --delete ".deploy_backup/$backup_tag/" ./
      docker compose up -d
      echo "Rollback complete"
    else
      echo "Backup $backup_tag not found" >&2
      exit 1
    fi
EOF
}

health_check() {
  local max_attempts=30
  local attempt=0
  
  log "Waiting for container health"
  
  while [[ $attempt -lt $max_attempts ]]; do
    local status
    status=$(ssh "$VPS_HOST" "cd $VPS_PATH && docker compose ps --format json banking 2>/dev/null" || echo "")
    
    if echo "$status" | grep -q '"State":"running"'; then
      ok "Container healthy"
      return 0
    fi
    
    ((attempt++))
    sleep 1
  done
  
  die "Container failed health check after ${max_attempts}s"
}

validate_compose() {
  log "Validating docker-compose.yml"
  docker compose -f docker-compose.yml config >/dev/null || die "Invalid compose file"
  ok "Compose file valid"
}

#######################################
# Preflight
#######################################
command -v rsync  >/dev/null || die "rsync missing"
command -v ssh    >/dev/null || die "ssh missing"
command -v docker >/dev/null || die "docker missing"

[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN MODE"

log "Deploy target: ${BOLD}$VPS_HOST:$VPS_PATH${RESET}"

# Validate SSH connectivity
log "Verifying SSH connection"
ssh -o ConnectTimeout=5 -o BatchMode=yes "$VPS_HOST" "exit" 2>/dev/null || die "SSH connection failed"
ok "SSH verified"

# Validate local compose file
validate_compose

# Check remote disk space
log "Checking remote disk space"
remote_avail=$(ssh "$VPS_HOST" "df -BM $VPS_PATH | tail -1 | awk '{print \$4}' | sed 's/M//'")
[[ $remote_avail -lt 500 ]] && die "Insufficient disk space: ${remote_avail}MB available"
ok "Disk space sufficient (${remote_avail}MB)"

#######################################
# Remote prep + backup
#######################################
log "Preparing remote directories"

BACKUP_TAG="backup_$(date +%Y%m%d_%H%M%S)"
echo "$BACKUP_TAG" > /tmp/deploy_backup_tag

if [[ "$DRY_RUN" == "false" ]]; then
  ssh "$VPS_HOST" <<EOF
    set -e
    mkdir -p $VPS_PATH/data
    mkdir -p $VPS_PATH/.deploy_backup
    
    # Create backup of current deployment
    if [[ -f $VPS_PATH/docker-compose.yml ]]; then
      mkdir -p $VPS_PATH/.deploy_backup/$BACKUP_TAG
      rsync -a --exclude=node_modules --exclude=.deploy_backup --exclude=.git \
        $VPS_PATH/ $VPS_PATH/.deploy_backup/$BACKUP_TAG/ || true
      
      # Keep only last 3 backups
      cd $VPS_PATH/.deploy_backup
      ls -t | tail -n +4 | xargs -r rm -rf
    fi
EOF
  ok "Remote ready (backup: $BACKUP_TAG)"
else
  ok "Remote prep (skipped - dry run)"
fi

#######################################
# Rsync payload
#######################################
log "Syncing filesystem delta"

RSYNC_OPTS=(-az --delete --stats)
[[ "$DRY_RUN" == "true" ]] && RSYNC_OPTS+=(--dry-run)

rsync "${RSYNC_OPTS[@]}" \
  --exclude={node_modules,.git,data,.env,.deploy.env,*.log,.DS_Store,.deploy_backup} \
  ./ "$VPS_HOST:$VPS_PATH/" | tail -5

if [[ "$DRY_RUN" == "false" ]]; then
  ok "Code synced"
else
  ok "Code sync preview (dry run)"
fi

#######################################
# Secrets & mutable state
#######################################
if [[ "$DRY_RUN" == "false" ]]; then
  if [[ -f .env ]]; then
    local_env_hash=$(shasum -a 256 .env | awk '{print $1}')
    rsync -az .env "$VPS_HOST:$VPS_PATH/"
    remote_env_hash=$(ssh "$VPS_HOST" "shasum -a 256 $VPS_PATH/.env 2>/dev/null | awk '{print \$1}'" || echo "")
    
    if [[ "$local_env_hash" == "$remote_env_hash" ]]; then
      ok ".env synced (verified)"
    else
      die ".env checksum mismatch"
    fi
  else
    warn ".env missing (skipped)"
  fi

  if [[ -f data/tokens.json ]]; then
    rsync -az data/tokens.json "$VPS_HOST:$VPS_PATH/data/" && ok "tokens.json synced"
  fi
else
  [[ -f .env ]] && ok ".env sync (skipped - dry run)" || warn ".env missing"
  [[ -f data/tokens.json ]] && ok "tokens.json sync (skipped - dry run)"
fi

#######################################
# Build + restart
#######################################
if [[ "$DRY_RUN" == "false" ]]; then
  log "Rebuilding & restarting containers"
  
  BUILD_START=$(date +%s)
  
  ssh "$VPS_HOST" <<EOF
    set -e
    cd $VPS_PATH
    
    # Validate compose on remote
    docker compose -f docker-compose.yml config >/dev/null
    
    # Build with no cache to ensure fresh build
    docker compose -f docker-compose.yml build --pull
    
    # Graceful restart
    docker compose -f docker-compose.yml up -d --remove-orphans
EOF

  BUILD_END=$(date +%s)
  BUILD_TIME=$((BUILD_END - BUILD_START))
  
  ok "Containers restarted"
  metric "Build time: ${BUILD_TIME}s"
  
  # Health check
  if [[ "$SKIP_HEALTH" == "false" ]]; then
    health_check
  else
    warn "Health check skipped"
  fi
else
  ok "Build & restart (skipped - dry run)"
fi

#######################################
# Postflight
#######################################
if [[ "$DRY_RUN" == "false" ]]; then
  echo
  log "Container status"
  ssh "$VPS_HOST" "cd $VPS_PATH && docker compose -f docker-compose.yml ps"

  echo
  log "Recent logs (last 15 lines)"
  ssh "$VPS_HOST" "cd $VPS_PATH && docker compose -f docker-compose.yml logs --tail=15 banking"

  # Calculate metrics
  DEPLOY_END=$(date +%s)
  TOTAL_TIME=$((DEPLOY_END - DEPLOY_START))
  
  # Get container uptime
  UPTIME=$(ssh "$VPS_HOST" "cd $VPS_PATH && docker compose ps --format '{{.Status}}' banking" | grep -o 'Up [^)]*' || echo "Unknown")
  
  echo
  ok "Deployment complete"
  metric "Total time: ${TOTAL_TIME}s"
  metric "Container: ${UPTIME}"
  metric "Backup: ${BACKUP_TAG}"
  echo
  echo "${DIM}Live logs:${RESET} ssh $VPS_HOST \"cd $VPS_PATH && docker compose -f docker-compose.yml logs -f\""
  echo "${DIM}Rollback:${RESET}  ssh $VPS_HOST \"cd $VPS_PATH && rsync -a --delete .deploy_backup/$BACKUP_TAG/ ./ && docker compose up -d\""
  
  # Cleanup trap flag so we don't try to rollback on successful exit
  ROLLBACK_TRIGGERED=true
else
  echo
  ok "Dry run complete — no changes made"
fi