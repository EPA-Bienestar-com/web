#!/usr/bin/env bash
# Publica www.epa-bienestar.com.ar:
#
#   /        → sitio actual, desde https://github.com/EPA-Developments/web
#   /2024/   → versión anterior (la que estaba publicada), archivada tal cual
#
#   sudo ./despliegue/publicar-sitio.sh
#
# Variables opcionales:
#   DESTINO      raíz que sirve nginx           (/var/www/epa-bienestar.com.ar)
#   REPO_WEB     repo del sitio actual           (https://github.com/EPA-Developments/web.git)
#   RAMA_WEB     rama del sitio actual           (main)
#   ORIGEN_2024  de dónde sale /2024 si todavía no existe y la raíz está vacía
#                (.tar.gz o carpeta; por defecto epa-bienestar-mayo.tar.gz de este repo)
#
# Si el repo del sitio no trae algún archivo, lo completa desde
# despliegue/complementos-2026/ (sin pisar nunca lo que venga en el repo).
#
# Es idempotente: /2024 se crea una sola vez y después no se toca. Cada corrida
# vuelve a bajar el sitio actual y reemplaza la raíz (salvo /2024 y /.well-known).
set -euo pipefail

DESTINO="${DESTINO:-/var/www/epa-bienestar.com.ar}"
REPO_WEB="${REPO_WEB:-https://github.com/EPA-Developments/web.git}"
RAMA_WEB="${RAMA_WEB:-main}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ORIGEN_2024="${ORIGEN_2024:-$REPO/epa-bienestar-mayo.tar.gz}"
ARCHIVO="$DESTINO/2024"

command -v rsync >/dev/null || { echo "Falta rsync: sudo apt-get install -y rsync" >&2; exit 1; }
command -v git   >/dev/null || { echo "Falta git: sudo apt-get install -y git" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DESTINO"

# Lo que nunca se publica: control de versiones, respaldos, generador y documentos internos.
EXCLUIR=(--exclude='.git' --exclude='.github' --exclude='*.bak*' --exclude='.DS_Store'
         --exclude='*.md' --exclude='LICENSE' --exclude='build.py' --exclude='*.py'
         --exclude='readme.1st' --exclude='snippet-*.html')

# ── 1. Archivar la versión anterior en /2024 (una sola vez) ──────────────────────────
if [[ -f "$ARCHIVO/index.html" ]]; then
    echo "· /2024 ya existe: no se toca."
else
    if [[ -f "$DESTINO/index.html" ]]; then
        echo "· Archivando la versión publicada hoy en $DESTINO → /2024"
        rsync -a "${EXCLUIR[@]}" --exclude='/2024/' --exclude='/.well-known/' "$DESTINO"/ "$TMP/2024"/
    else
        echo "· La raíz está vacía: /2024 sale de $ORIGEN_2024"
        if [[ -d "$ORIGEN_2024" ]]; then
            rsync -a "${EXCLUIR[@]}" "$ORIGEN_2024"/ "$TMP/2024"/
        else
            mkdir -p "$TMP/paquete" && tar xzf "$ORIGEN_2024" -C "$TMP/paquete"
            rsync -a "${EXCLUIR[@]}" "$(dirname "$(find "$TMP/paquete" -maxdepth 2 -name index.html -print -quit)")"/ "$TMP/2024"/
        fi
    fi
    # Los enlaces absolutos a la portada ("/", "/index.html") sacarían al visitante del
    # archivo hacia el sitio nuevo: se vuelven relativos para que /2024 sea navegable.
    find "$TMP/2024" -maxdepth 1 -name '*.html' -exec \
        sed -i -E 's#href="/(index\.html)?"#href="index.html"#g' {} +
    mkdir -p "$ARCHIVO"
    rsync -a "$TMP/2024"/ "$ARCHIVO"/
fi

# ── 2. Bajar el sitio actual ─────────────────────────────────────────────────────────
echo "· Bajando $REPO_WEB ($RAMA_WEB)"
git clone -q --depth 1 --branch "$RAMA_WEB" "$REPO_WEB" "$TMP/repo"
echo "  commit $(git -C "$TMP/repo" log -1 --format='%h %ad %s' --date=short)"
mkdir -p "$TMP/nuevo"
rsync -a "${EXCLUIR[@]}" "$TMP/repo"/ "$TMP/nuevo"/

# El repo no trae las imágenes (LEEME.md: «copiá tu carpeta assets/img/ actual»).
# Se completan con las de la versión archivada, sin pisar las que sí vengan en el repo.
if [[ -d "$ARCHIVO/assets/img" ]]; then
    rsync -a --ignore-existing "$ARCHIVO/assets/img"/ "$TMP/nuevo/assets/img"/
fi

# Complementos: archivos que el sitio necesita y su repo todavía no trae
# (hoy, assets/js/epa-analytics.js). Nunca pisan lo que venga en el repo:
# el día que el repo los incluya, gana la versión del repo.
if [[ -d "$REPO/despliegue/complementos-2026" ]]; then
    rsync -a --ignore-existing --out-format='  complemento: %n' \
        "$REPO/despliegue/complementos-2026"/ "$TMP/nuevo"/ | grep -v '/$' || true
fi

# ── 3. Avisar qué referencia el sitio y no existe ───────────────────────────────────
while IFS= read -r pagina; do
    dir="$(dirname "$pagina")"
    { grep -oE '(src|href)="[^"#?]+"' "$pagina" || true; } | sed -E 's/^(src|href)="//; s/"$//' |
        { grep -vE '^(https?:|mailto:|tel:|data:|javascript:|//)' || true; } |
        while IFS= read -r ref; do
            if [[ "$ref" == /* ]]; then f="$TMP/nuevo$ref"; else f="$dir/$ref"; fi
            rel="$(realpath -m --relative-to="$TMP/nuevo" "$f")"
            # /2024 no viene en el repo: vive en el destino.
            [[ -e "$f" || -e "$f.html" ]] && continue
            [[ ( "$rel" == 2024 || "$rel" == 2024/* ) && -e "$DESTINO/$rel" ]] && continue
            echo "$rel"
        done | sort -u
done < <(find "$TMP/nuevo" -name '*.html') | sort | uniq -c > "$TMP/faltan"
if [[ -s "$TMP/faltan" ]]; then
    echo "  Archivos que el sitio referencia y no existen:"
    awk '{printf "    /%s  (en %d páginas)\n", $2, $1}' "$TMP/faltan"
fi

# ── 4. Publicar ──────────────────────────────────────────────────────────────────────
rsync -a --delete --exclude='/2024/' --exclude='/.well-known/' "$TMP/nuevo"/ "$DESTINO"/
chown -R root:root "$DESTINO"
find "$DESTINO" -type d -exec chmod 755 {} +
find "$DESTINO" -type f -exec chmod 644 {} +

echo "· Publicado en $DESTINO (sitio actual) y $ARCHIVO (versión 2024)."
if [[ -s "$TMP/faltan" ]]; then
    echo "  Ojo: faltan los archivos listados arriba. Lo ideal es subirlos al repo del sitio." >&2
fi
