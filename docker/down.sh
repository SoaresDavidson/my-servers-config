#!/bin/sh
# Derruba as stacks. Sem argumentos, todas; ou passe nomes: ./down.sh sonarr
# A rede compartilhada é external: não é removida aqui, só pelo docker.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_env_file
resolve_stacks "$@"

printf '%s' "$STACK_PATHS" | while IFS= read -r stack; do
  printf '%s\n' "derrubando $(basename "$stack")..."
  docker compose --env-file "$ENV_FILE" -f "$stack/docker-compose.yml" down
done
