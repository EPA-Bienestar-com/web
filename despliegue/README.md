# Despliegue de www.epa-bienestar.com.ar

Mismo servidor y mismo esquema que `info-biowellness` e `info-pb100d`: un archivo en
`/etc/nginx/sites-available/`, symlink en `sites-enabled/` y Certbot para HTTPS.

| Dominio | Qué hace |
|---|---|
| `https://www.epa-bienestar.com.ar` | Sirve el sitio (canónico; info-pb100d ya redirige acá `/acerca_de_nosotros.html`, `/politica_de_privacidad.html` y `/condiciones_del_servicio.html`) |
| `https://epa-bienestar.com.ar` | 301 → `https://www.epa-bienestar.com.ar` (misma ruta) |
| `http://…` (ambos) | 301 → HTTPS (lo agrega Certbot) |

Archivos:

- `nginx/www-epa-bienestar` → `/etc/nginx/sites-available/www-epa-bienestar`
- `publicar-sitio.sh` → copia el HTML a `/var/www/epa-bienestar.com.ar`

## 0. DNS (antes de Certbot)

Los dos nombres tienen que apuntar a la IP pública de esta instancia (registro A, y AAAA si hay IPv6):

```bash
curl -s https://checkip.amazonaws.com
```

```bash
dig +short epa-bienestar.com.ar A; dig +short www.epa-bienestar.com.ar A
```

Las tres IP deben coincidir. `www` puede ser un CNAME a `epa-bienestar.com.ar`.
El Security Group de EC2 tiene que abrir 80 y 443.

## 1. Publicar el contenido

```bash
cd ~ && git clone https://github.com/EPA-Bienestar-com/web.git epa-web
```

```bash
sudo apt-get install -y rsync && sudo ~/epa-web/despliegue/publicar-sitio.sh
```

Sin argumento publica `epa-bienestar-mayo.tar.gz`. Si tenés una versión más nueva del sitio,
pasala como argumento (un `.tar.gz` o una carpeta con `index.html`).

## 2. Habilitar el sitio en nginx

```bash
sudo cp ~/epa-web/despliegue/nginx/www-epa-bienestar /etc/nginx/sites-available/www-epa-bienestar
```

```bash
sudo ln -s /etc/nginx/sites-available/www-epa-bienestar /etc/nginx/sites-enabled/www-epa-bienestar
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Prueba por HTTP, antes del certificado:

```bash
curl -sI -H 'Host: www.epa-bienestar.com.ar' http://127.0.0.1/ | head -1
```

## 3. HTTPS con Certbot

Un solo certificado para los dos nombres:

```bash
sudo certbot --nginx -d www.epa-bienestar.com.ar -d epa-bienestar.com.ar
```

Cuando pregunte, elegí redirigir HTTP → HTTPS. Certbot edita el archivo igual que hizo con
los otros dos (marca sus líneas con `# managed by Certbot`).

Si `nginx -t` falla después con `duplicate listen options for [::]:443`, es porque Certbot
puso `ipv6only=on` también acá y ya está en `info-pb100d`: borralo de este archivo y dejá
`listen [::]:443 ssl;`.

## 4. Verificar

```bash
curl -sI https://www.epa-bienestar.com.ar/ | head -1
```

```bash
curl -sI https://epa-bienestar.com.ar/acerca_de_nosotros.html | grep -i '^location'
```

```bash
curl -sI http://www.epa-bienestar.com.ar/ | grep -i '^location'
```

```bash
curl -sI https://www.epa-bienestar.com.ar/.git/config | head -1
```

Esperado: `200`, `https://www.epa-bienestar.com.ar/acerca_de_nosotros.html`,
`https://www.epa-bienestar.com.ar/` y `404`.

## Actualizar el sitio

Repetir el paso 1 (`git pull` y `publicar-sitio.sh`). No hace falta recargar nginx.
