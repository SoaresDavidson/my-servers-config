#!/bin/sh
set -u

# --- Configurações ---
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOCKER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../docker" && pwd)
STACKS_DIR="$DOCKER_DIR/stacks"
ENV_FILE="$DOCKER_DIR/.env"
STATE_DIR="$DOCKER_DIR/.state"
mkdir -p "$STATE_DIR"

# Cores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_err() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

if [ ! -f "$ENV_FILE" ]; then
  log_err "Arquivo $ENV_FILE não encontrado. Execute $SCRIPT_DIR/setup-env.sh primeiro."
  exit 1
fi

# Função para verificar se a stack está saudável
is_stack_healthy() {
  local stack_path=$1
  # Extrai nomes de containers definidos no compose
  containers=$(docker compose -f "$stack_path" ps --format "{{.Name}}" 2>/dev/null)

  if [ -z "$containers" ]; then return 1; fi

  for container in $containers; do
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
    if [ "$status" != "healthy" ]; then
      return 1
    fi
  done
  return 0
}

# Função para verificar se houve mudanças nos arquivos
has_changes() {
  local stack_path=$1
  local state_file="$STATE_DIR/$(basename "$(dirname "$stack_path")").last_boot"

  # Se o arquivo de estado não existe, houve mudança
  if [ ! -f "$state_file" ]; then return 0; fi

  # Compara data de modificação do compose e do .env
  if [ "$stack_path" -nt "$state_file" ] || [ "$ENV_FILE" -nt "$state_file" ]; then
    return 0
  fi
  return 1
}

# --- Execução ---

# 1. Stack Shared (Sempre primeiro e aguarda health)
log_info "Iniciando stack shared..."
docker compose --env-file "$ENV_FILE" -f "$STACKS_DIR/shared/docker-compose.yml" up -d

# Aguarda a stack shared ficar saudável
timeout=60
elapsed=0
while ! is_stack_healthy "$STACKS_DIR/shared/docker-compose.yml"; do
  if [ $elapsed -ge $timeout ]; then
    log_err "Timeout aguardando stack shared ficar saudável."
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
log_info "Stack shared está saudável."

# 2. Demais Stacks
failed_stacks=""

for stack_dir in "$STACKS_DIR"/*/; do
  name=$(basename "$stack_dir")
  [ "$name" = shared ] && continue

  compose_file="$stack_dir/docker-compose.yml"
  [ ! -f "$compose_file" ] && continue

  if is_stack_healthy "$compose_file" && ! has_changes "$compose_file"; then
    log_info "Stack $name já está saudável e sem alterações. Pulando..."
    continue
  fi

  log_info "Subindo/Atualizando stack $name..."
  if docker compose --env-file "$ENV_FILE" -f "$compose_file" up -d; then
    touch "$STATE_DIR/$(basename "$stack_dir").last_boot"
  else
    log_err "Falha ao subir stack $name."
    failed_stacks="$failed_stacks $name"
  fi
done

if [ -n "$failed_stacks" ]; then
  log_err "As seguintes stacks falharam: $failed_stacks"
  exit 1
fi

log_info "Todas as stacks foram processadas com sucesso!"
