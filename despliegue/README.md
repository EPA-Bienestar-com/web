# Despliegue de www.epa-bienestar.com.ar

Mismo servidor y mismo esquema que `info-biowellness` e `info-pb100d`: un archivo en
`/etc/nginx/sites-available/`, symlink en `sites-enabled/` y Certbot para HTTPS.

| URL | Qué sirve |
|---|---|
| `https://www.epa-bienestar.com.ar/` | **Sitio actual**, de [EPA-Developments/web](https://github.com/EPA-Developments/web) (canónico) |
| `https://www.epa-bienestar.com.ar/2024/` | **Versión anterior**, archivada tal cual estaba publicada (`X-Robots-Tag: noindex`) |
| `https://www.epa-bienestar.com.ar/fhir/…` | Recursos FHIR R4 (`application/fhir+json`, CORS abierto) |
| `https://epa-bienestar.com.ar/…` | 301 → `https://www.epa-bienestar.com.ar/…` (misma ruta) |
| `http://…` (ambos) | 301 → HTTPS (lo agrega Certbot) |

Archivos:

- `nginx/www-epa-bienestar` → `/etc/nginx/sites-available/www-epa-bienestar`
- `publicar-sitio.sh` → arma `/var/www/epa-bienestar.com.ar` (raíz + `/2024`)

## Qué hace `publicar-sitio.sh`

1. **Archiva la versión anterior en `/2024`, una sola vez.** Si en la raíz ya hay un sitio
   publicado, lo copia tal cual a `/2024`. Si la raíz está vacía, usa
   `epa-bienestar-mayo.tar.gz` (o lo que indique `ORIGEN_2024`). Los enlaces
   `href="/"` de esas páginas se vuelven relativos para que el archivo sea navegable.
   Una vez creado, `/2024` no se vuelve a tocar.
2. **Baja el sitio actual** de `EPA-Developments/web` (rama `main`, o `RAMA_WEB`).
3. **Completa las imágenes.** El repo no trae `assets/img/` (lo dice su `LEEME.md`), así
   que copia las de `/2024/assets/img` sin pisar las que vengan en el repo.
4. **Avisa qué falta**: cualquier archivo que alguna página referencie y no exista.
5. **Publica** en la raíz con `rsync --delete`, respetando `/2024` y `/.well-known`.
   Nunca publica `.git`, `*.md`, `build.py`, `LICENSE`, `snippet-*.html` ni respaldos `*.bak*`.

Se puede correr las veces que haga falta: cada corrida trae lo último del repo del sitio.

## 0. Antes de empezar

DNS: los dos nombres tienen que apuntar a la IP pública de esta instancia. Además, el
Security Group de EC2 tiene que abrir los puertos 80 y 443.

```bash
curl -s https://checkip.amazonaws.com; dig +short epa-bienestar.com.ar A; dig +short www.epa-bienestar.com.ar A
```

Fijate qué carpeta sirve hoy el sitio. Si no es `/var/www/epa-bienestar.com.ar`, corré el
script con `DESTINO=<esa carpeta>`, o cambiá el `root` del archivo de nginx.

```bash
sudo nginx -T 2>/dev/null | grep -nE 'server_name|root' | grep -A1 'epa-bienestar.com.ar'
```

## 1. Publicar

```bash
sudo apt-get install -y git rsync
```

```bash
cd ~ && (git clone -b claude/great-keller-sntgw3 https://github.com/EPA-Bienestar-com/web.git epa-web || git -C epa-web pull)
```

```bash
sudo ~/epa-web/despliegue/publicar-sitio.sh
```

## 2. nginx

```bash
sudo cp ~/epa-web/despliegue/nginx/www-epa-bienestar /etc/nginx/sites-available/www-epa-bienestar
```

```bash
sudo ln -sf /etc/nginx/sites-available/www-epa-bienestar /etc/nginx/sites-enabled/www-epa-bienestar
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Si el archivo ya estaba instalado y Certbot ya lo había editado, **no lo pises con `cp`**:
perderías las líneas `# managed by Certbot`. En ese caso agregá a mano los bloques
`location ^~ /2024/` y `location ^~ /fhir/` del archivo del repo.

## 3. HTTPS con Certbot (solo la primera vez)

```bash
sudo certbot --nginx -d www.epa-bienestar.com.ar -d epa-bienestar.com.ar
```

Si después `nginx -t` falla con `duplicate listen options for [::]:443`, es porque Certbot
puso `ipv6only=on` también acá y ya está en `info-pb100d`. Borralo de este archivo.

## 4. Verificar

```bash
for u in / /2024/ /menopausia.html /fhir/CodeSystem-epa-index.json /build.py /2024/.git/config; do printf '%-36s ' "$u"; curl -s -o /dev/null -w '%{http_code}\n' "https://www.epa-bienestar.com.ar$u"; done
```

Esperado: `200 200 200 200 404 404`. Y el dominio sin www redirige:

```bash
curl -sI https://epa-bienestar.com.ar/2024/ | grep -i '^location'
```

## Pendientes del sitio actual (repo EPA-Developments/web)

Esto lo detecta el script y hay que resolverlo en ese repo, no acá:

- `assets/js/epa-analytics.js`: lo cargan las 14 páginas, pero **no está en el repo**.
  Sin ese archivo no hay Consent Mode ni medición del embudo (ver `MEDICION.md` de ese repo).
- `assets/img/8pasos_AHA.jpg` (home) y `assets/img/favicon.ico`: el script los toma de
  `/2024/assets/img` si están ahí. Si no, hay que subirlos.
