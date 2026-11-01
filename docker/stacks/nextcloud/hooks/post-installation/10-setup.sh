#!/bin/sh
# Roda como www-data uma única vez, logo após a instalação automática.
# Faz o que fica no banco e não precisa ser reaplicado a cada start.
set -eu

occ() { php /var/www/html/occ "$@"; }

# Editor de documentos; a configuração do app é reaplicada pelo before-starting.
occ app:install onlyoffice

# HD de mídia como pasta "Mídia": só leitura e sem prévias (ver README).
occ app:enable files_external
mount_id=$(occ files_external:create Mídia local null::null -c datadir=/mnt/midia --output=json)
occ files_external:option "$mount_id" readonly true
occ files_external:option "$mount_id" previews false
