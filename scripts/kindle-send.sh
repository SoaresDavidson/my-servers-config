#!/usr/bin/env bash
#
# Converte livros que estao no servidor e entrega no Kindle plugado nesta maquina.
#
# Tudo do lado do servidor roda dentro do container do Calibre, que e root e
# enxerga a biblioteca inteira. O usuario SSH normalmente nao consegue ler as
# pastas dos livros (o *arr cria como root 750), entao ele so le o staging.
# Os originais no servidor nunca sao alterados nem apagados.
#
# Uso:
#   ./kindle-send.sh <pasta-no-servidor> [opcoes]
#
# Exemplo:
#   ./kindle-send.sh /DATA/Media/media/books/inbox
#
# Opcoes:
#   -s, --server USER@HOST   Destino SSH do servidor (padrao: davi@192.168.100.35)
#   -c, --container NOME     Container do Calibre (padrao: calibre)
#   -m, --map HOST:CONT      Mapeamento do volume (padrao: /DATA/Media/media:/data/media)
#   -d, --dest SUBPASTA      Subpasta no Kindle (padrao: documents)
#   -l, --label ROTULO       Rotulo da particao do Kindle (padrao: Kindle)
#   -f, --force              Reenvia livros que ja estao no Kindle
#   -k, --keep-mounted       Nao desmonta o Kindle no final
#   -n, --dry-run            Mostra o plano, sem converter nem copiar
#   -h, --help               Esta ajuda

set -euo pipefail

# Extensoes que o KOReader abre nativamente. Converter so piora (PDF e HQ sobretudo).
NATIVAS="epub pdf mobi azw3 fb2 djvu cbz cbr txt html htm chm"

SERVIDOR="davi@192.168.100.35"
CONTAINER="calibre"
MAPEAMENTO="/DATA/Media/media:/data/media"
DEST_SUB="documents"
LABEL="Kindle"
FORCE=0
KEEP_MOUNTED=0
DRY_RUN=0
ORIGEM=""

uso() { sed -n '2,26p' "$0" | sed 's/^# \?//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--server)       SERVIDOR="$2"; shift 2 ;;
    -c|--container)    CONTAINER="$2"; shift 2 ;;
    -m|--map)          MAPEAMENTO="$2"; shift 2 ;;
    -d|--dest)         DEST_SUB="$2"; shift 2 ;;
    -l|--label)        LABEL="$2"; shift 2 ;;
    -f|--force)        FORCE=1; shift ;;
    -k|--keep-mounted) KEEP_MOUNTED=1; shift ;;
    -n|--dry-run)      DRY_RUN=1; shift ;;
    -h|--help)         uso; exit 0 ;;
    -*)                echo "Opcao desconhecida: $1" >&2; exit 1 ;;
    *)                 ORIGEM="$1"; shift ;;
  esac
done

[[ -z "$ORIGEM" ]] && { uso >&2; exit 1; }

MAP_HOST="${MAPEAMENTO%%:*}"
MAP_CONT="${MAPEAMENTO##*:}"

case "$ORIGEM" in
  "$MAP_HOST"/*) : ;;
  *) echo "A pasta precisa estar dentro de $MAP_HOST (volume que o container enxerga)." >&2
     echo "Use --map se o seu mapeamento for outro." >&2
     exit 1 ;;
esac

for cmd in ssh tar udisksctl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd nao encontrado." >&2; exit 1; }
done

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$SERVIDOR" true 2>/dev/null; then
  echo "Sem acesso SSH por chave a $SERVIDOR." >&2
  echo "Rode uma vez: ssh-copy-id $SERVIDOR" >&2
  exit 1
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

DESTINO="$MONTAGEM/$DEST_SUB"
MANIFESTO="$(mktemp)"
STAGE_CONT=""

limpar() {
  # O staging e escrito como root pelo container, entao quem apaga e o container.
  [[ -n "$STAGE_CONT" ]] && \
    ssh "$SERVIDOR" docker exec "$CONTAINER" rm -rf -- "$STAGE_CONT" 2>/dev/null || true
  rm -f "$MANIFESTO"
  if [[ $MONTADO_POR_NOS -eq 1 && $KEEP_MOUNTED -eq 0 ]]; then
    sync
    udisksctl unmount -b "$DISPOSITIVO" >/dev/null 2>&1 \
      && echo "Kindle desmontado. Pode desconectar." \
      || echo "Nao consegui desmontar o Kindle. Desmonte antes de desconectar." >&2
  fi
}
trap limpar EXIT

echo "Servidor: $SERVIDOR"
echo "Origem:   $ORIGEM"
echo "Destino:  $DESTINO"
[[ $DRY_RUN -eq 1 ]] && echo "(dry-run: nada sera convertido nem copiado)"
echo

# Livros ja no Kindle, para nao reconverter a toa.
JA_TEM=""
if [[ $FORCE -eq 0 && -d "$DESTINO" ]]; then
  JA_TEM="$(cd "$DESTINO" && ls -1 2>/dev/null | base64 -w0)"
fi

# --- Fase remota: tudo dentro do container ----------------------------------

# ssh nao cita os argumentos: o shell remoto reparte a linha de novo, quebrando
# valores com espaco e engolindo os vazios. Um blob base64 atravessa intacto.
PARAMS="$(printf '%s\0' \
  "$ORIGEM" "$MAP_HOST" "$MAP_CONT" "$CONTAINER" "$NATIVAS" "$JA_TEM" "$DRY_RUN" \
  | base64 -w0)"

ssh "$SERVIDOR" bash -s -- "$PARAMS" > "$MANIFESTO" <<'REMOTO'
set -euo pipefail
mapfile -d '' PARAMS < <(printf '%s' "$1" | base64 -d)
ORIGEM="${PARAMS[0]}"; MAP_HOST="${PARAMS[1]}"; MAP_CONT="${PARAMS[2]}"
CONTAINER="${PARAMS[3]}"; NATIVAS="${PARAMS[4]}"; JA_TEM_B64="${PARAMS[5]}"
DRY_RUN="${PARAMS[6]}"

# Progresso vai para stderr; o manifesto (stdout) e consumido pelo script local.
log() { echo "$*" >&2; }
dentro() { docker exec "$CONTAINER" "$@"; }

# Separa "sem permissao no docker.sock" de "container parado": sintomas iguais.
if ! estado="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>&1)"; then
  if grep -qi 'permission denied' <<<"$estado"; then
    log "Usuario $(whoami) nao tem acesso ao docker no servidor."
    log "Corrija no servidor: sudo usermod -aG docker $(whoami)"
    log "(o grupo so vale em sessao SSH nova; feche as antigas)"
  else
    log "Container '$CONTAINER' nao existe no servidor: $estado"
  fi
  exit 1
fi
[[ "$estado" == true ]] || { log "Container '$CONTAINER' existe mas esta parado."; exit 1; }

ORIGEM_CONT="$MAP_CONT/${ORIGEM#$MAP_HOST/}"
dentro test -d "$ORIGEM_CONT" || { log "Pasta nao existe no servidor: $ORIGEM"; exit 1; }

JA_TEM_LISTA=""
[[ -n "$JA_TEM_B64" ]] && JA_TEM_LISTA="$(printf '%s' "$JA_TEM_B64" | base64 -d)"

ja_existe() { [[ -n "$JA_TEM_LISTA" ]] && grep -Fxq -- "$1" <<<"$JA_TEM_LISTA"; }
e_nativa() { local n; for n in $NATIVAS; do [[ "$1" == "$n" ]] && return 0; done; return 1; }

STAGE_CONT=""
STAGE_HOST=""
if [[ "$DRY_RUN" -eq 0 ]]; then
  SUFIXO="kindle-stage-$$"
  STAGE_CONT="$MAP_CONT/.$SUFIXO"
  STAGE_HOST="$MAP_HOST/.$SUFIXO"
  dentro mkdir -p "$STAGE_CONT"
  echo "STAGE	$STAGE_CONT	$STAGE_HOST"
fi

declare -A VISTOS=()

# Nome unico no staging: dois livros podem ter o mesmo basename em pastas diferentes.
unico() {
  local nome="$1" base ext n=2
  [[ -z "${VISTOS[$nome]:-}" ]] && { VISTOS[$nome]=1; printf '%s' "$nome"; return; }
  base="${nome%.*}"; ext="${nome##*.}"
  while [[ -n "${VISTOS[$base ($n).$ext]:-}" ]]; do n=$((n + 1)); done
  VISTOS["$base ($n).$ext"]=1
  printf '%s' "$base ($n).$ext"
}

# A varredura roda dentro do container: o usuario SSH nao le as pastas dos livros.
while IFS= read -r -d '' arquivo; do
  nome="$(basename "$arquivo")"
  base="${nome%.*}"
  ext="$(printf '%s' "${nome##*.}" | tr '[:upper:]' '[:lower:]')"

  if e_nativa "$ext"; then alvo="$nome"; acao=COPY; else alvo="$base.epub"; acao=CONV; fi

  if ja_existe "$alvo"; then
    log "[ja no Kindle] $nome"
    continue
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[$acao] $nome -> $alvo"
    continue
  fi

  final="$(unico "$alvo")"

  if [[ "$acao" == COPY ]]; then
    if dentro cp -- "$arquivo" "$STAGE_CONT/$final" 2>/dev/null; then
      log "[copiado] $nome"
      printf 'FILE\t%s\n' "$final"
    else
      log "[falhou] $nome - nao consegui copiar para o staging"
    fi
    continue
  fi

  if saida="$(dentro ebook-convert "$arquivo" "$STAGE_CONT/$final" 2>&1)"; then
    log "[convertido] $nome -> $final"
    printf 'FILE\t%s\n' "$final"
  elif grep -qi drm <<<"$saida"; then
    log "[DRM] $nome - protegido, precisa do plugin DeDRM"
  else
    log "[falhou] $nome - $(grep -iE 'error|Traceback' <<<"$saida" | tail -1)"
  fi
done < <(dentro find "$ORIGEM_CONT" -type f -not -path '*/.*' -print0 | sort -z)

# O container grava como root; solta a leitura para o usuario SSH puxar via rsync.
[[ -n "$STAGE_CONT" ]] && dentro chmod -R a+rX "$STAGE_CONT"
exit 0
REMOTO

STAGE_CONT="$(awk -F'\t' '$1=="STAGE"{print $2; exit}' "$MANIFESTO")"
STAGE_HOST="$(awk -F'\t' '$1=="STAGE"{print $3; exit}' "$MANIFESTO")"

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "Fim do dry-run."
  exit 0
fi

# --- Fase local: puxa o staging para o Kindle -------------------------------

TOTAL="$(awk -F'\t' '$1=="FILE"' "$MANIFESTO" | wc -l)"
if [[ "$TOTAL" -eq 0 ]]; then
  echo
  echo "Nada novo para enviar."
  exit 0
fi

mkdir -p "$DESTINO"
echo
echo "Transferindo $TOTAL arquivo(s) para o Kindle..."

# tar em vez de rsync: o servidor nao tem rsync, e o staging ja e plano e
# contem exatamente o que vai para o Kindle. --no-same-owner porque vfat ignora dono.
ssh "$SERVIDOR" tar -C "$STAGE_HOST" -cf - . \
  | tar -C "$DESTINO" -xf - --no-same-owner

echo "Enviados: $TOTAL"
