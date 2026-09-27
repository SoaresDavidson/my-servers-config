#!/bin/sh
# Copia as chaves de API dos apps para o docker/.env, como HOMEPAGE_VAR_*.
# Nada é impresso além do nome de cada variável gravada.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/../docker/.env"

if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "Arquivo $ENV_FILE não encontrado. Execute $SCRIPT_DIR/setup-env.sh primeiro." >&2
  exit 1
fi

CONFIG_HOST_PATH=$(sed -n 's/^CONFIG_HOST_PATH=//p' "$ENV_FILE")

set_var() {
  name=$1
  value=$2
  if [ -z "$value" ]; then
    printf '%s\n' "$name: chave não encontrada, pulando." >&2
    return
  fi
  tmp=$(mktemp "$ENV_FILE.XXXXXX")
  grep -v "^$name=" "$ENV_FILE" >"$tmp" || true
  printf '%s=%s\n' "$name" "$value" >>"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ENV_FILE"
  printf '%s\n' "$name gravada."
}

arr_key() {
  sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$CONFIG_HOST_PATH/$1/config/config.xml" 2>/dev/null
}

set_var HOMEPAGE_VAR_SONARR_KEY "$(arr_key sonarr)"
set_var HOMEPAGE_VAR_RADARR_KEY "$(arr_key radarr)"
set_var HOMEPAGE_VAR_LIDARR_KEY "$(arr_key lidarr)"
set_var HOMEPAGE_VAR_PROWLARR_KEY "$(arr_key prowlarr)"
set_var HOMEPAGE_VAR_BOOKSHELF_KEY "$(arr_key bookshelf)"

# Bazarr: auth.apikey no config.yaml.
set_var HOMEPAGE_VAR_BAZARR_KEY "$(awk '/^auth:/{a=1;next} /^[^ ]/{a=0} a && $1=="apikey:"{print $2; exit}' \
  "$CONFIG_HOST_PATH/bazarr/config/config/config.yaml" 2>/dev/null | tr -d "'\"")"

# Jellyseerr: main.apiKey no settings.json.
set_var HOMEPAGE_VAR_JELLYSEERR_KEY "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["main"]["apiKey"])' \
  "$CONFIG_HOST_PATH/jellyseerr/config/settings.json" 2>/dev/null || true)"
