#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOCKER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../docker" && pwd)
STACKS_DIR="$DOCKER_DIR"
ENV_FILE="$DOCKER_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "Arquivo $ENV_FILE não encontrado. Execute $SCRIPT_DIR/setup-env.sh primeiro." >&2
  exit 1
fi

failed_stacks=""

for stack in "$STACKS_DIR"/*/*/; do
  name=$(basename "$stack")
  # Hermes agora roda no host; imagens com build local não vêm do registry.
  [ "$name" = hermes ] && continue
  [ -f "$stack/docker-compose.yml" ] || continue
  printf '%s\n' "Baixando imagens da stack $name..."
  if ! docker compose --env-file "$ENV_FILE" -f "$stack/docker-compose.yml" pull --ignore-buildable; then
    printf '%s\n' "Falha ao baixar imagens da stack $name." >&2
    failed_stacks="$failed_stacks $name"
  fi
done

printf '%s\n' "Recriando as stacks com as imagens atualizadas..."
"$SCRIPT_DIR/up-all.sh"

if [ -n "$failed_stacks" ]; then
  printf '%s\n' "Imagens disponíveis aplicadas, mas houve falha no download das stacks:$failed_stacks" >&2
  exit 1
fi

printf '%s\n' "Containers atualizados com sucesso."
