#!/bin/bash
REPO=/home/davi/server-config
mkdir -p $REPO/casaos-apps

sudo find /var/lib/casaos/apps -mindepth 1 -maxdepth 1 -type d | while read appdir; do
  app=$(basename "$appdir")
  mkdir -p "$REPO/casaos-apps/$app"
  sudo cp "$appdir/docker-compose.yml" "$REPO/casaos-apps/$app/" 2>/dev/null
done

echo "Compose files do CasaOS copiados para $REPO/casaos-apps/"
