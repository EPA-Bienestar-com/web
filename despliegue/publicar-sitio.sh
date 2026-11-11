#!/usr/bin/env bash
# Publica el sitio institucional en /var/www/epa-bienestar.com.ar.
#
#   sudo ./despliegue/publicar-sitio.sh [paquete.tar.gz | carpeta]
#
# Sin argumento usa epa-bienestar-mayo.tar.gz de la raíz del repo.
# Nunca copia .git ni respaldos (*.bak*), y deja todo legible por nginx (www-data).
set -euo pipefail

DESTINO="${DESTINO:-/var/www/epa-bienestar.com.ar}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ORIGEN="${1:-$REPO/epa-bienestar-mayo.tar.gz}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -d "$ORIGEN" ]]; then
    SITIO="$ORIGEN"
else
    tar xzf "$ORIGEN" -C "$TMP"
    # El paquete trae todo dentro de una carpeta (epa-bienestar/).
    SITIO="$(dirname "$(find "$TMP" -maxdepth 2 -name index.html -print -quit)")"
fi
[[ -f "$SITIO/index.html" ]] || { echo "No encuentro index.html en $ORIGEN" >&2; exit 1; }

mkdir -p "$DESTINO"
rsync -a --delete \
    --exclude='.git' --exclude='.well-known' --exclude='*.bak*' --exclude='.DS_Store' \
    "$SITIO"/ "$DESTINO"/
chown -R root:root "$DESTINO"
find "$DESTINO" -type d -exec chmod 755 {} +
find "$DESTINO" -type f -exec chmod 644 {} +

echo "Publicado en $DESTINO:"
ls "$DESTINO"
