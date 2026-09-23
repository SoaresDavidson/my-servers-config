#!/usr/bin/env bash
#
# Caminho inverso do kindle-send.sh: pega os livros KFX do Kindle, tira o DRM e
# converte para EPUB no servidor, e devolve o EPUB para o proprio Kindle, onde o
# KOReader consegue abrir. KFX e formato fechado da Amazon; o KOReader nao le.
#
# Um livro KFX nao e um arquivo so: e o .kfx em documents/ mais a pasta .sdr
# irma, que guarda o voucher e o conteudo real em assets/attachables/.
# Os dois precisam viajar juntos, senao o DeDRM nao acha a chave.
#
# O DRM so sai com o numero de serie deste Kindle registrado no DeDRM.
# Le em Ajustes > Informacoes do dispositivo e registre uma vez:
#   ./kindle-fetch.sh --serial G000XXXXXXXXXXXX
#
# Uso:
#   ./kindle-fetch.sh [opcoes]
#
# Opcoes:
#   --serial SERIAL          Registra o serial do Kindle no DeDRM e sai
#   -s, --server USER@HOST   Destino SSH do servidor (padrao: davi@192.168.100.35)
#   -c, --container NOME     Container do Calibre (padrao: calibre)
#   -d, --dest SUBPASTA      Subpasta no Kindle (padrao: documents)
#   -l, --label ROTULO       Rotulo da particao do Kindle (padrao: Kindle)
#   -f, --force              Reprocessa livros que ja tem EPUB no Kindle
#   -k, --keep-mounted       Nao desmonta o Kindle no final
#   -n, --dry-run            Lista o que seria processado, sem mexer em nada
#   -h, --help               Esta ajuda

set -euo pipefail

SERVIDOR="davi@192.168.100.35"
CONTAINER="calibre"
DEST_SUB="documents"
LABEL="Kindle"
SERIAL=""
FORCE=0
KEEP_MOUNTED=0
DRY_RUN=0

uso() { sed -n '2,29p' "$0" | sed 's/^# \?//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)          SERIAL="$2"; shift 2 ;;
    -s|--server)       SERVIDOR="$2"; shift 2 ;;
    -c|--container)    CONTAINER="$2"; shift 2 ;;
    -d|--dest)         DEST_SUB="$2"; shift 2 ;;
    -l|--label)        LABEL="$2"; shift 2 ;;
    -f|--force)        FORCE=1; shift ;;
    -k|--keep-mounted) KEEP_MOUNTED=1; shift ;;
    -n|--dry-run)      DRY_RUN=1; shift ;;
    -h|--help)         uso; exit 0 ;;
    *)                 echo "Opcao desconhecida: $1" >&2; exit 1 ;;
  esac
done

for cmd in ssh tar udisksctl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd nao encontrado." >&2; exit 1; }
done

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$SERVIDOR" true 2>/dev/null; then
  echo "Sem acesso SSH por chave a $SERVIDOR." >&2
  echo "Rode uma vez: ssh-copy-id $SERVIDOR" >&2
  exit 1
fi

# --- Registrar serial e sair ------------------------------------------------

if [[ -n "$SERIAL" ]]; then
  ssh "$SERVIDOR" docker exec -i "$CONTAINER" python3 - "$SERIAL" <<'PY'
import json, os, sys
serial = sys.argv[1]
p = "/config/.config/calibre/plugins/dedrm.json"
cfg = json.load(open(p)) if os.path.exists(p) else {}
cfg.setdefault("serials", [])
if serial not in cfg["serials"]:
    cfg["serials"].insert(0, serial)
json.dump(cfg, open(p, "w"), indent=2)
print("serials registrados:", cfg["serials"])
PY
  exit 0
fi

# --- Monta o Kindle ---------------------------------------------------------

DISPOSITIVO="/dev/disk/by-label/$LABEL"
[[ -e "$DISPOSITIVO" ]] || { echo "Nenhuma particao com rotulo '$LABEL'. Kindle conectado e em modo USB?" >&2; exit 1; }

MONTADO_POR_NOS=0
MONTAGEM="$(lsblk -no MOUNTPOINT "$DISPOSITIVO" | head -1)"
if [[ -z "$MONTAGEM" ]]; then
  udisksctl mount -b "$DISPOSITIVO" >/dev/null
  MONTAGEM="$(lsblk -no MOUNTPOINT "$DISPOSITIVO" | head -1)"
  MONTADO_POR_NOS=1
fi
[[ -n "$MONTAGEM" ]] || { echo "Falha ao montar $DISPOSITIVO." >&2; exit 1; }

DOCS="$MONTAGEM/$DEST_SUB"
[[ -d "$DOCS" ]] || { echo "Nao achei $DOCS no Kindle." >&2; exit 1; }

TRABALHO="$(mktemp -d)"
REMOTO_TMP=""

limpar() {
  rm -rf "$TRABALHO"
  [[ -n "$REMOTO_TMP" ]] && \
    ssh "$SERVIDOR" docker exec "$CONTAINER" rm -rf -- "$REMOTO_TMP" 2>/dev/null || true
  if [[ $MONTADO_POR_NOS -eq 1 && $KEEP_MOUNTED -eq 0 ]]; then
    sync
    udisksctl unmount -b "$DISPOSITIVO" >/dev/null 2>&1 \
      && echo "Kindle desmontado. Pode desconectar." \
      || echo "Nao consegui desmontar o Kindle. Desmonte antes de desconectar." >&2
  fi
}
trap limpar EXIT

echo "Kindle:   $DOCS"
echo "Servidor: $SERVIDOR"
[[ $DRY_RUN -eq 1 ]] && echo "(dry-run: nada sera processado)"
echo

# --- Seleciona os KFX -------------------------------------------------------

mapfile -t KFX < <(find "$DOCS" -maxdepth 1 -name '*.kfx' -printf '%f\n' | sort)

ALVOS=()
for nome in "${KFX[@]}"; do
  base="${nome%.kfx}"
  if [[ $FORCE -eq 0 && -e "$DOCS/$base.epub" ]]; then
    echo "[ja tem EPUB] $base"
    continue
  fi
  if [[ ! -d "$DOCS/$base.sdr" ]]; then
    echo "[sem .sdr]    $base - o conteudo real mora na pasta .sdr, sem ela nao da"
    continue
  fi
  echo "[processar]   $base"
  ALVOS+=("$base")
done

if [[ ${#ALVOS[@]} -eq 0 ]]; then
  echo
  echo "Nada para processar."
  exit 0
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "Fim do dry-run. ${#ALVOS[@]} livro(s) entrariam."
  exit 0
fi

# --- Manda .kfx + .sdr para o servidor --------------------------------------

REMOTO_TMP="/tmp/kindle-fetch-$$"
ssh "$SERVIDOR" docker exec "$CONTAINER" mkdir -p "$REMOTO_TMP/entrada" "$REMOTO_TMP/saida"

echo
echo "Enviando ${#ALVOS[@]} livro(s) para o servidor..."
PACOTE=()
for base in "${ALVOS[@]}"; do PACOTE+=("$base.kfx" "$base.sdr"); done
tar -C "$DOCS" -cf - -- "${PACOTE[@]}" \
  | ssh "$SERVIDOR" docker exec -i "$CONTAINER" tar -C "$REMOTO_TMP/entrada" -xf -

# --- Fase remota: DeDRM no import + conversao -------------------------------

# O DeDRM so roda ao adicionar numa biblioteca (e plugin de import), nunca no
# ebook-convert direto. E a GUI do Calibre segura um lock por uid, entao o CLI
# roda como outro uid, com uma copia do config dir para enxergar os plugins.
ssh "$SERVIDOR" bash -s -- "$(printf '%s\0' "$CONTAINER" "$REMOTO_TMP" | base64 -w0)" <<'REMOTO'
set -euo pipefail
mapfile -d '' P < <(printf '%s' "$1" | base64 -d)
CONTAINER="${P[0]}"; TMP="${P[1]}"

dentro() { docker exec "$CONTAINER" "$@"; }
cli() { docker exec -u 1000:1000 -e CALIBRE_CONFIG_DIRECTORY="$TMP/cfg" -e HOME="$TMP" "$CONTAINER" "$@"; }

dentro cp -a /config/.config/calibre "$TMP/cfg"
dentro mkdir -p "$TMP/lib"
dentro chown -R 1000:1000 "$TMP"

# find -print0 em vez de $(ls): nome de livro tem espaco, e word splitting
# quebrava "Uma senhora toma cha.kfx" em quatro "livros".
while IFS= read -r -d '' kfx; do
  nome="$(basename "$kfx")"
  base="${nome%.kfx}"
  echo "-- $base" >&2

  rm_id=""
  if ! saida="$(cli calibredb add --with-library="$TMP/lib" "$kfx" 2>&1)"; then
    echo "   [falhou no add] $(grep -iE 'error|exception' <<<"$saida" | tail -1)" >&2
    continue
  fi
  rm_id="$(grep -oE 'Added book ids: [0-9]+' <<<"$saida" | grep -oE '[0-9]+$' || true)"
  [[ -z "$rm_id" ]] && { echo "   [nao adicionou]" >&2; continue; }

  if grep -qi 'DRM' <<<"$saida"; then
    echo "   [DRM intacto] serial do Kindle nao confere - registre com --serial" >&2
    continue
  fi

  dentro mkdir -p "$TMP/export/$rm_id"
  dentro chown -R 1000:1000 "$TMP/export"
  if ! cli calibredb export --with-library="$TMP/lib" --to-dir="$TMP/export/$rm_id" \
         --single-dir --dont-write-opf --dont-save-cover "$rm_id" >/dev/null 2>&1; then
    echo "   [falhou no export]" >&2
    continue
  fi

  livro="$(dentro sh -c "ls -1 '$TMP/export/$rm_id'/* 2>/dev/null | head -1")"
  [[ -z "$livro" ]] && { echo "   [export vazio]" >&2; continue; }

  if cli ebook-convert "$livro" "$TMP/saida/$base.epub" >/dev/null 2>&1; then
    echo "   [ok] $base.epub" >&2
  else
    echo "   [falhou na conversao]" >&2
  fi
done < <(dentro find "$TMP/entrada" -maxdepth 1 -name '*.kfx' -print0)

dentro chmod -R a+rX "$TMP/saida"
REMOTO

# --- Traz os EPUBs de volta -------------------------------------------------

PRONTOS="$(ssh "$SERVIDOR" docker exec "$CONTAINER" \
  find "$REMOTO_TMP/saida" -maxdepth 1 -name '*.epub' -printf 'x\n' 2>/dev/null | wc -l)"
if [[ "$PRONTOS" -eq 0 ]]; then
  echo
  echo "Nenhum EPUB gerado."
  exit 1
fi

echo
echo "Trazendo $PRONTOS EPUB(s) para o Kindle..."
ssh "$SERVIDOR" docker exec "$CONTAINER" tar -C "$REMOTO_TMP/saida" -cf - . \
  | tar -C "$DOCS" -xf - --no-same-owner

echo "Prontos: $PRONTOS"
