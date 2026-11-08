#!/bin/sh
# Loop de scan do ClamAV. Usa clamscan, sem daemon clamd: a base de assinaturas (~1 GB de RAM)
# só fica carregada enquanto o scan roda.
#
# A cada SCAN_INTERVAL segundos, atualiza a base e escaneia os arquivos de /data cujo ctime é
# posterior ao último scan. Usa ctime, não mtime, porque o qBittorrent move o arquivo da pasta
# temp ao terminar e o *arr cria hardlink na biblioteca: as duas coisas mudam o ctime, não o mtime.
# A cada FULL_SCAN_DAYS dias (0 desliga), escaneia tudo de novo, para pegar o que só passou a ser
# detectado depois.
#
# Vídeo e áudio ficam de fora: não são executados e são a maior parte do volume. Um executável
# renomeado para .mkv também não roda, porque é a extensão que decide o que o sistema faz.
# Achados vão para o log do container (Dozzle) e para /state/infected.log.
set -u

INTERVAL=${SCAN_INTERVAL:-3600}
FULL_DAYS=${FULL_SCAN_DAYS:-7}
MAX_SIZE=${MAX_FILESIZE:-2000M}
STATE=/state
LIST=/tmp/scan-list
OUT=/tmp/scan-out
SKIP_EXT='\.(mkv|mk3d|mp4|m4v|avi|mov|wmv|webm|flv|mpg|mpeg|m2ts|ts|vob|ogv|flac|mp3|m4a|m4b|aac|ogg|opus|wav|wma|ape|wv|srt|sub|idx|ass|ssa|vtt|nfo|jpg|jpeg|png|webp)$'

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

mkdir -p "$STATE"
chown -R clamav:clamav /var/lib/clamav

while true; do
  freshclam --stdout --quiet || log "freshclam falhou, seguindo com a base atual"

  now=$(date +%s)
  since=$(cat "$STATE/last-scan" 2>/dev/null || echo 0)
  last_full=$(cat "$STATE/last-full-scan" 2>/dev/null || echo 0)
  full=0
  if [ "$FULL_DAYS" -gt 0 ] && [ $((now - last_full)) -ge $((FULL_DAYS * 86400)) ]; then
    full=1
    since=0
  fi

  # Downloads/temp tem os torrents incompletos, que ainda vão mudar.
  find /data -type f ! -path '/data/Downloads/temp/*' -exec stat -c '%Z %n' {} + \
    | awk -v since="$since" -v skip="$SKIP_EXT" \
        '$1 >= since { sub(/^[0-9]+ /, ""); if (tolower($0) !~ skip) print }' >"$LIST"
  count=$(wc -l <"$LIST")

  rc=0
  if [ "$count" -gt 0 ]; then
    [ "$full" = 1 ] && kind="scan completo" || kind="scan incremental"
    log "$kind: $count arquivo(s)"
    clamscan --infected --no-summary --max-filesize="$MAX_SIZE" --max-scansize="$MAX_SIZE" \
      --file-list="$LIST" >"$OUT" 2>&1
    rc=$?
    cat "$OUT"
    if [ "$rc" = 1 ]; then
      grep ' FOUND$' "$OUT" | while IFS= read -r line; do
        log "$line" | tee -a "$STATE/infected.log"
      done
      log "ALERTA: arquivo(s) infectado(s) encontrado(s). Lista em infected.log."
    fi
  fi

  # rc 2 é erro do clamscan (base ausente, arquivo ilegível): repete a mesma janela na próxima volta.
  if [ "$rc" -lt 2 ]; then
    echo "$now" >"$STATE/last-scan"
    [ "$full" = 1 ] && echo "$now" >"$STATE/last-full-scan"
  else
    log "clamscan terminou com erro ($rc); a janela será escaneada de novo"
  fi

  sleep "$INTERVAL"
done
