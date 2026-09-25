#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOCKER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../docker" && pwd)
ENV_FILE="$DOCKER_DIR/.env"
STACKS_DIR="$DOCKER_DIR/stacks"

if [ -e "$ENV_FILE" ]; then
  printf '%s\n' ".env já existe em $ENV_FILE. Edite manualmente ou remova antes de executar script."
  exit 1
fi

if [ ! -d "$STACKS_DIR" ]; then
  printf '%s\n' "diretório stacks/ não encontrado em $DOCKER_DIR."
  exit 1
fi

suggest_timezone() {
  if [ -L /etc/localtime ]; then
    timezone=$(readlink /etc/localtime 2>/dev/null || true)
    case "$timezone" in
      */zoneinfo/*)
        printf '%s\n' "${timezone#*/zoneinfo/}"
        return
        ;;
    esac
  fi

  printf '%s\n' UTC
}

prompt_value() {
  label=$1
  default=$2
  secret=${3:-false}

  if [ "$secret" = true ] && [ -t 0 ]; then
    printf '%s' "$label: " >&2
    stty -echo
    IFS= read -r value
    stty echo
    printf '\n' >&2
  elif [ "$secret" = true ]; then
    printf '%s' "$label: " >&2
    IFS= read -r value
  else
    printf '%s' "$label [$default]: " >&2
    IFS= read -r value
  fi

  if [ -z "$value" ]; then
    value=$default
  fi

  if [ -z "$value" ]; then
    printf '%s\n' "$label não pode ficar vazio." >&2
    exit 1
  fi

  printf '%s\n' "$value"
}

require_absolute_path() {
  label=$1
  value=$2

  case "$value" in
    /*) ;;
    *)
      printf '%s\n' "$label deve ser caminho absoluto: $value" >&2
      exit 1
      ;;
  esac
}

puid=$(id -u)
pgid=$(id -g)
timezone=$(suggest_timezone)

ts_authkey=$(prompt_value 'TS_AUTHKEY' '' true)
network_name=$(prompt_value 'NETWORK_NAME' 'medianet')
config_host_path=$(prompt_value 'CONFIG_HOST_PATH' '/DATA/AppData/media-stack')
data_host_path=$(prompt_value 'DATA_HOST_PATH' '/DATA')
backup_passphrase=$(prompt_value 'BACKUP_PASSPHRASE (guarde fora do servidor)' '' true)

require_absolute_path 'CONFIG_HOST_PATH' "$config_host_path"
require_absolute_path 'DATA_HOST_PATH' "$data_host_path"

umask 077
cat >"$ENV_FILE" <<EOF
TS_AUTHKEY=$ts_authkey
PUID=$puid
PGID=$pgid
TZ=$timezone
NETWORK_NAME=$network_name
CONFIG_HOST_PATH=$config_host_path
DATA_HOST_PATH=$data_host_path
BACKUP_PASSPHRASE=$backup_passphrase
EOF
chmod 600 "$ENV_FILE"

for stack in "$STACKS_DIR"/*/; do
  ln -sfn ../../.env "$stack/.env"
done

if ! docker network inspect "$network_name" >/dev/null 2>&1; then
  docker network create "$network_name" >/dev/null
  printf '%s\n' "rede $network_name criada."
fi

for stack in "$STACKS_DIR"/*/; do
  name=$(basename "$stack")
  if ! docker compose --env-file "$ENV_FILE" -f "$stack/docker-compose.yml" config >/dev/null; then
    printf '%s\n' ".env criado, mas docker compose config falhou na stack $name. Corrija $ENV_FILE e valide manualmente." >&2
    exit 1
  fi
done

printf '%s\n' ".env criado e todas as stacks validadas: $ENV_FILE"
