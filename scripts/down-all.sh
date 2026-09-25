#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOCKER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../docker" && pwd)
STACKS_DIR="$DOCKER_DIR/stacks"
ENV_FILE="$DOCKER_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "Arquivo $ENV_FILE não encontrado. Execute $SCRIPT_DIR/setup-env.sh primeiro." >&2
  exit 1
fi

# Derruba as aplicações antes dos serviços auxiliares da stack shared.
for stack in "$STACKS_DIR"/*/; do
  name=$(basename "$stack")
  [ "$name" = shared ] && continue
  docker compose --env-file "$ENV_FILE" -f "$stack/docker-compose.yml" down
done

docker compose --env-file "$ENV_FILE" -f "$STACKS_DIR/shared/docker-compose.yml" down
