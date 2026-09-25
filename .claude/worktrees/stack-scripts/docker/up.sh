#!/bin/sh
# Sobe as stacks. Sem argumentos, todas; ou passe nomes: ./up.sh sonarr radarr
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_env_file
resolve_stacks "$@"

network_name=$(env_value NETWORK_NAME)
if [ -z "$network_name" ]; then
  printf '%s\n' "NETWORK_NAME não definido em $ENV_FILE." >&2
  exit 1
fi

if ! docker network inspect "$network_name" >/dev/null 2>&1; then
  docker network create "$network_name" >/dev/null
  printf '%s\n' "rede $network_name criada."
fi

printf '%s' "$STACK_PATHS" | while IFS= read -r stack; do
  printf '%s\n' "subindo $(basename "$stack")..."
  docker compose --env-file "$ENV_FILE" -f "$stack/docker-compose.yml" up -d
done
