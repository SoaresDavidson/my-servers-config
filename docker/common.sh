#!/bin/sh
# Helpers compartilhados pelos scripts deste diretório. Carregue com ". common.sh".
# Depende de $0 apontar para um script dentro de docker/.

DOCKER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$DOCKER_DIR/.env"
STACKS_DIR="$DOCKER_DIR/stacks"

if [ ! -d "$STACKS_DIR" ]; then
  printf '%s\n' "diretório stacks/ não encontrado em $DOCKER_DIR." >&2
  exit 1
fi

require_env_file() {
  if [ ! -f "$ENV_FILE" ]; then
    printf '%s\n' "$ENV_FILE não existe. Execute $DOCKER_DIR/setup-env.sh primeiro." >&2
    exit 1
  fi
}

# Lê uma chave do .env sem interpretar o arquivo como shell.
env_value() {
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

# Preenche STACK_PATHS com um caminho de stack por linha. Sem argumentos, todas
# as stacks que têm docker-compose.yml; com argumentos, apenas as nomeadas.
resolve_stacks() {
  STACK_PATHS=''

  if [ "$#" -eq 0 ]; then
    for stack in "$STACKS_DIR"/*/; do
      [ -f "$stack/docker-compose.yml" ] || continue
      STACK_PATHS="$STACK_PATHS${stack%/}
"
    done
  else
    for name in "$@"; do
      stack="$STACKS_DIR/$name"
      if [ ! -f "$stack/docker-compose.yml" ]; then
        printf '%s\n' "stack $name não encontrada em $STACKS_DIR." >&2
        exit 1
      fi
      STACK_PATHS="$STACK_PATHS$stack
"
    done
  fi

  if [ -z "$STACK_PATHS" ]; then
    printf '%s\n' "nenhuma stack com docker-compose.yml em $STACKS_DIR." >&2
    exit 1
  fi
}
