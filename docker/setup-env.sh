#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

if [ -e "$ENV_FILE" ]; then
  printf '%s\n' ".env já existe em $ENV_FILE. Edite manualmente ou remova antes de executar script."
  exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
  printf '%s\n' "docker-compose.yml não encontrado em $SCRIPT_DIR."
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
downloads_host_path=$(prompt_value 'DOWNLOADS_HOST_PATH' '')
media_host_path=$(prompt_value 'MEDIA_HOST_PATH' '')
container_downloads_path=$(prompt_value 'CONTAINER_DOWNLOADS_PATH' '/data/downloads')
container_media_path=$(prompt_value 'CONTAINER_MEDIA_PATH' '/data/media')

require_absolute_path 'DOWNLOADS_HOST_PATH' "$downloads_host_path"
require_absolute_path 'MEDIA_HOST_PATH' "$media_host_path"
require_absolute_path 'CONTAINER_DOWNLOADS_PATH' "$container_downloads_path"
require_absolute_path 'CONTAINER_MEDIA_PATH' "$container_media_path"

umask 077
cat >"$ENV_FILE" <<EOF
TS_AUTHKEY=$ts_authkey
PUID=$puid
PGID=$pgid
TZ=$timezone
NETWORK_NAME=$network_name
DOWNLOADS_HOST_PATH=$downloads_host_path
CONTAINER_DOWNLOADS_PATH=$container_downloads_path
MEDIA_HOST_PATH=$media_host_path
CONTAINER_MEDIA_PATH=$container_media_path
EOF
chmod 600 "$ENV_FILE"

if ! docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config >/dev/null; then
  printf '%s\n' ".env criado, mas docker compose config falhou. Corrija $ENV_FILE e execute validação manualmente." >&2
  exit 1
fi

printf '%s\n' ".env criado e validado: $ENV_FILE"
