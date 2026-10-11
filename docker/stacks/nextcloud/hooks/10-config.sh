#!/bin/sh
# Roda como www-data a cada start, depois de instalar/atualizar e antes do Apache.
# Reaplica o que as variáveis NEXTCLOUD_* só gravam na instalação.
set -eu

occ() { php /var/www/html/occ "$@"; }

# Tailnet (via tailscale serve), LAN (porta 7580) e o OnlyOffice pela rede Docker.
occ config:system:set trusted_domains 0 --value=localhost
occ config:system:set trusted_domains 1 --value="nextcloud.$TS_DOMAIN"
occ config:system:set trusted_domains 2 --value="$HOST_LAN_IP"
occ config:system:set trusted_domains 3 --value=tailscale-nextcloud

# Background jobs pelo container cron, não por AJAX nas visitas.
occ background:cron

# O app onlyoffice fala com o Document Server por um IP da rede Docker; o cliente HTTP do
# Nextcloud bloqueia endereços privados sem isto.
occ config:system:set allow_local_remote_servers --value=true --type=boolean

# App onlyoffice. O navegador só conhece o tailnet; servidor <-> servidor vai pela rede Docker.
occ config:app:set onlyoffice DocumentServerUrl --value="https://onlyoffice.$TS_DOMAIN/"
occ config:app:set onlyoffice DocumentServerInternalUrl --value=http://tailscale-onlyoffice/
occ config:app:set onlyoffice StorageUrl --value=http://tailscale-nextcloud/
occ config:app:set onlyoffice jwt_secret --value="$ONLYOFFICE_JWT_SECRET"
