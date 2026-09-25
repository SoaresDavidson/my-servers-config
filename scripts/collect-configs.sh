#!/bin/bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
mkdir -p "$REPO_DIR/casaos-apps"

sudo find /var/lib/casaos/apps -mindepth 1 -maxdepth 1 -type d | while IFS= read -r appdir; do
  app=$(basename "$appdir")
  mkdir -p "$REPO_DIR/casaos-apps/$app"
  sudo cp "$appdir/docker-compose.yml" "$REPO_DIR/casaos-apps/$app/" 2>/dev/null
done

echo "Compose files do CasaOS copiados para $REPO_DIR/casaos-apps/"
