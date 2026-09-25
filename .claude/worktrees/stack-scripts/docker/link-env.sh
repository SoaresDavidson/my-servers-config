#!/bin/sh
# Cria em cada stack o symlink .env -> ../../.env, para que "docker compose"
# rodado de dentro do diretório da stack encontre as variáveis.
# Sem argumentos, todas as stacks; ou passe nomes: ./link-env.sh sonarr radarr
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_env_file
resolve_stacks "$@"

printf '%s' "$STACK_PATHS" | while IFS= read -r stack; do
  ln -sfn ../../.env "$stack/.env"
  printf '%s\n' "symlink .env criado em $(basename "$stack")."
done
