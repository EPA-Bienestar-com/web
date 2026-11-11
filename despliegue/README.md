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

## Salida a producción del sitio 2026 — checklist

Lo que falta, en orden. Los pasos 1 a 3 se hacen una sola vez.

### 1. Aplicar los parches en EPA-Developments/web

En `parches/` están los dos commits para ese repo. Desde tu copia de `EPA-Developments/web`:

```bash
git am ~/epa-web/despliegue/parches/*.patch && git push
```

| Parche | Qué hace |
|---|---|
| `0001-Footer-…` | Enlace «Versión 2024» en el footer de las 15 páginas (y en `build.py`) |
| `0002-Agregar-assets-js-epa-analytics.js-…` | **El archivo que faltaba.** Las 14 páginas cargan `gtag.js`, pero el `gtag('config', 'G-5J3NZ57F9D')` vive en este archivo: sin él, GA4 no registra ni una visita |

Mientras el parche 0002 no esté en el repo, `publicar-sitio.sh` publica la misma copia
desde `complementos-2026/`. Cuando el repo lo incluya, gana la versión del repo.

### 2. Que `info.` no pierda el origen del clic

Los botones del sitio llevan a `info.epa-bienestar.com.ar/evaluacion-inicial.php?epa_src=…&epa_cta=…`.
La regla actual de `info-pb100d` redirige a `/donde-hacerlo/` **y descarta esos parámetros**:
el embudo queda sin origen (lo probé con nginx). En `/etc/nginx/sites-available/info-pb100d`, cambiar:

```nginx
location ~ ^/evaluacion-inicial(\.php)?/?$ { return 301 /donde-hacerlo/$is_args$args; }
location ~ ^/turnos(\.php)?/?$ { return 301 /donde-hacerlo/$is_args$args; }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Y la página de destino tiene que llevar el mismo measurement ID: el contenido de
`snippet-evaluacion-inicial.html` (en el repo del sitio) va en `/donde-hacerlo/`, que es donde
hoy termina la evaluación.

### 3. GA4 (antes de mandar tráfico: no es retroactivo)

En la propiedad `G-5J3NZ57F9D`:

- **Admin → Definiciones personalizadas → ámbito Evento**: `origen_pagina`, `origen_cta`, `cta_id`,
  `cta_destination`, `page_group`, `page_slug`, `faq_pregunta`, `paso`.
- **Admin → Eventos → evento clave**: `evaluacion_completa` y `salida_evaluacion`.
- **Admin → Flujos de datos → Configurar etiqueta → Configurar dominios**:
  `epa-bienestar.com.ar`, `info.epa-bienestar.com.ar`, `mujer.epa-bienestar.com.ar`.

### 4. Imágenes que faltan

`publicar-sitio.sh` avisa al final. Hoy: `assets/img/8pasos_AHA.jpg` (home) y
`assets/img/favicon.ico`. Si el sitio publicado hoy los tiene, salen de `/2024/assets/img`.
Si no, hay que subirlos al repo del sitio.

### 5. Publicar y verificar

```bash
cd ~/epa-web && git pull && sudo ./despliegue/publicar-sitio.sh
```

En el navegador: aparece el aviso de analítica abajo a la izquierda. En DevTools → Red,
filtrando por `collect`, cada clic en «Evaluación inicial» manda `salida_evaluacion`.
Después, en GA4 → Informes → **Tiempo real**, tienen que aparecer las visitas.

## Qué mide `epa-analytics.js`

Implementa `MEDICION.md` del repo del sitio:

- **Consent Mode v2.** La publicidad está denegada siempre. La analítica está concedida
  por defecto, con aviso para desactivarla. Para California hay que cambiar `ANALYTICS_DEFAULT`
  a `"denied"`. Quien desactiva la analítica no envía nada (`ga-disable`), y la preferencia
  queda en el navegador.
- **Eventos:** `cta_click`, `salida_evaluacion`, `profundidad_lectura` (25/50/75/90),
  `faq_abierta`, `reconocimiento_usado` (una vez, sin contenido) y `cambio_tema`. Todos llevan
  `page_slug` y `page_group`.
- **`SEND_SYMPTOM_COUNT = false`:** ningún dato de salud sale hacia GA4.
- **Enlaces a `info.`:** llevan `epa_src`/`epa_cta`, nunca `utm_*`.
