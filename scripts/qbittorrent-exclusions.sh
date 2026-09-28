#!/bin/sh
# Grava no qBittorrent (via WebAPI) a lista de arquivos que nunca são baixados.
# Rodar no servidor, depois de trocar a lista ou reinstalar o qBittorrent.
#
# A lista vale para todas as categorias, inclusive "game" (Questarr), então não inclui .exe, .bat
# nem arquivos compactados, que jogos usam de verdade. Nas categorias dos *arr, esses tipos já
# são barrados pelo REMOVE_BAD_FILES do Decluttarr (stack shared). Aqui ficam só tipos que não
# têm uso legítimo em torrent nenhum: atalhos, protetores de tela e scripts do Windows Script Host.
# .js fica de fora: jogos em RPG Maker MV/MZ e HTML5 são feitos dele.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="$SCRIPT_DIR/../docker/.env"
QBIT_URL=${QBIT_URL:-http://localhost:8080}

PATTERNS='*.lnk
*.url
*.scr
*.pif
*.hta
*.cpl
*.vbs
*.vbe
*.jse
*.wsf
*.wsh'

if [ ! -f "$ENV_FILE" ]; then
  printf '%s\n' "Arquivo $ENV_FILE não encontrado. Execute $SCRIPT_DIR/setup-env.sh primeiro." >&2
  exit 1
fi

user=$(sed -n 's/^QBITTORRENT_USERNAME=//p' "$ENV_FILE")
pass=$(sed -n 's/^QBITTORRENT_PASSWORD=//p' "$ENV_FILE")
cookies=$(mktemp)
trap 'rm -f "$cookies"' EXIT

curl -fsS -c "$cookies" --data-urlencode "username=$user" --data-urlencode "password=$pass" \
  "$QBIT_URL/api/v2/auth/login" >/dev/null

prefs=$(PATTERNS="$PATTERNS" python3 -c \
  'import json, os; print(json.dumps({"excluded_file_names_enabled": True, "excluded_file_names": os.environ["PATTERNS"]}))')
curl -fsS -b "$cookies" --data-urlencode "json=$prefs" "$QBIT_URL/api/v2/app/setPreferences"

printf '%s\n' "Lista de exclusão gravada:"
curl -fsS -b "$cookies" "$QBIT_URL/api/v2/app/preferences" \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["excluded_file_names"])'
