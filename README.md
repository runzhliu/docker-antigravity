# docker-antigravity

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

Run [Antigravity](https://antigravity.app) in a Docker container with a browser-accessible GUI via Selkies — no local installation required.

**Note:** This project is not published as a pre-built image on any registry. You must build it locally before running.

[中文文档 README_ZH.md](README_ZH.md)

---

## Demo

<video src="https://github.com/user-attachments/assets/9c1bb5f6-06c5-40e1-815a-8d0cd5113077" controls width="100%"></video>

---

## Building Locally

> **Note:** `linuxserver/chrome:latest` only publishes a `linux/amd64` image. The Dockerfile pins `--platform=linux/amd64` so builds work on ARM hosts (e.g. Apple Silicon) via QEMU emulation. [BuildKit](https://docs.docker.com/build/buildkit/) is recommended for faster, more reliable builds.

```bash
git clone https://github.com/runzhliu/docker-antigravity.git
cd docker-antigravity
DOCKER_BUILDKIT=1 docker build -t docker-antigravity:latest .
```

---

## Quick Start

```bash
docker run -d \
  --name=antigravity \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=UTC \
  -e CUSTOM_USER=your-username \
  -e PASSWORD=your-password \
  -p 3000:3000 \
  -p 3001:3001 \
  -v ./config:/config \
  --shm-size="1gb" \
  --restart unless-stopped \
  docker-antigravity:latest
```

Open **https://localhost:3001** in your browser.

> **Self-signed certificate warning:** Port 3001 uses HTTPS with a self-signed certificate issued by Linuxserver.io. Your browser will show a security warning on first visit — click **Advanced → Proceed to localhost** to continue. This is expected for local or LAN use. To get a trusted certificate with no browser warning, see [Let's Encrypt HTTPS](#lets-encrypt-https-optional) below.

### Docker Compose

```yaml
services:
  antigravity:
    image: docker-antigravity:latest
    container_name: antigravity
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - CUSTOM_USER=your-username   # required for public deployments
      - PASSWORD=your-password      # required for public deployments
    volumes:
      - ./config:/config
    ports:
      - 3000:3000   # Selkies web UI (HTTP)
      - 3001:3001   # Selkies web UI (HTTPS, self-signed cert)
    shm_size: "1gb"
    restart: unless-stopped
```

---

## Let's Encrypt HTTPS (Optional)

For public deployments with a real domain, the image can automatically obtain and renew a trusted Let's Encrypt certificate. The certificate is installed into the nginx SSL paths inside the container, so the built-in HTTPS on port 3001 serves a trusted cert with no browser warning.

**Requirements:**
- A public domain name pointing to the host machine
- Port 80 reachable from the internet (for the ACME HTTP-01 challenge)
- Port 443 not already in use on the host (e.g. stop any existing reverse proxy on that port)

**Usage:**

```bash
docker run -d \
  --name=antigravity \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=UTC \
  -e CUSTOM_USER=your-username \
  -e PASSWORD=your-password \
  -e DOMAIN=antigravity.example.com \
  -e LETSENCRYPT_EMAIL=you@example.com \
  -p 80:80 \
  -p 443:3001 \
  -v ./config:/config \
  --shm-size="1gb" \
  --sysctl net.ipv6.conf.all.disable_ipv6=1 \
  --restart unless-stopped \
  docker-antigravity:latest
```

Then open **https://antigravity.example.com** in your browser — no security warning.

**How it works:**
1. On first start, certbot obtains a certificate via HTTP-01 challenge (standalone mode, port 80).
2. The certificate is written to `/config/ssl/cert.pem` and `/config/ssl/cert.key` — the paths nginx reads for TLS on port 3001.
3. nginx serves the Let's Encrypt certificate on port 3001, mapped to host port 443.
4. A weekly cron job (Monday 03:00) renews the certificate automatically and reloads nginx — no downtime or restart needed.
5. The certificate is persisted in `/config/ssl/` across container restarts.

> **Note:** `--sysctl net.ipv6.conf.all.disable_ipv6=1` is required so certbot binds to IPv4 (port 80) correctly for the HTTP-01 challenge. Without it, certbot may only bind IPv6 and the CA validation will fail with "Connection refused".

If `DOMAIN` or `LETSENCRYPT_EMAIL` is not set, the container falls back to the built-in self-signed certificate on port 3001 (see browser warning note in Quick Start).

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | User ID for file permissions |
| `PGID` | `1000` | Group ID for file permissions |
| `TZ` | `UTC` | Timezone (e.g. `Asia/Shanghai`) |
| `CUSTOM_USER` | — | HTTP Basic Auth username for the web UI |
| `PASSWORD` | — | HTTP Basic Auth password for the web UI |
| `DOMAIN` | — | Public domain name for Let's Encrypt certificate |
| `LETSENCRYPT_EMAIL` | — | Email address for Let's Encrypt registration |

Full list of inherited variables: [linuxserver/chrome docs](https://docs.linuxserver.io/images/docker-chrome)

---

## Volumes

| Path | Description |
|------|-------------|
| `/config` | Antigravity profile, preferences, and user data |

---

## How it Works

1. Builds on [`linuxserver/chrome`](https://docs.linuxserver.io/images/docker-chrome), which provides a lightweight Openbox desktop streamed via [Selkies-GStreamer](https://github.com/selkies-project/selkies-gstreamer) (WebRTC). An nginx reverse proxy inside the container handles HTTPS on port 3001.
2. Installs Antigravity from Google Artifact Registry's official Debian repository.
3. Wraps `google-chrome-stable` to always pass `--no-sandbox` (required inside Docker).
4. Creates `wrapped-antigravity` — a launcher that cleans up stale lock files and passes required flags.
5. Replaces the default autostart so Antigravity launches automatically on container start.
6. A `custom-cont-init.d` script handles first-run setup: `argv.json`, Openbox menu entry, and autostart migration.
7. If `DOMAIN` and `LETSENCRYPT_EMAIL` are set, a second init script obtains a Let's Encrypt certificate via certbot and writes it to `/config/ssl/cert.pem` and `cert.key` — the paths nginx uses for TLS on port 3001. Mapping host port 443 to container port 3001 exposes standard HTTPS. A weekly cron job handles automatic renewal with nginx reload (no downtime).

---

## Contributing

PRs and issues are welcome. Please open an issue before submitting a large change.

---

## Disclaimer

This image/script is for personal academic research purposes only. Users are responsible for complying with Google's Terms of Service.

---

## License

MIT
