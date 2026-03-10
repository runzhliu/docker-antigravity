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

```bash
git clone https://github.com/runzhliu/docker-antigravity.git
cd docker-antigravity
docker build -t docker-antigravity:latest .
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
      - 3001:3001   # Selkies web UI (HTTPS, recommended)
    shm_size: "1gb"
    restart: unless-stopped
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | User ID for file permissions |
| `PGID` | `1000` | Group ID for file permissions |
| `TZ` | `UTC` | Timezone (e.g. `Asia/Shanghai`) |
| `CUSTOM_USER` | — | HTTP Basic Auth username for the web UI |
| `PASSWORD` | — | HTTP Basic Auth password for the web UI |

Full list of inherited variables: [linuxserver/chrome docs](https://docs.linuxserver.io/images/docker-chrome)

---

## Volumes

| Path | Description |
|------|-------------|
| `/config` | Antigravity profile, preferences, and user data |

---

## How it Works

1. Builds on [`linuxserver/chrome`](https://docs.linuxserver.io/images/docker-chrome), which provides a lightweight Openbox desktop streamed via [Selkies-GStreamer](https://github.com/selkies-project/selkies-gstreamer) (WebRTC).
2. Installs Antigravity from Google Artifact Registry's official Debian repository.
3. Wraps `google-chrome-stable` to always pass `--no-sandbox` (required inside Docker).
4. Creates `wrapped-antigravity` — a launcher that cleans up stale lock files and passes required flags.
5. Replaces the default autostart so Antigravity launches automatically on container start.
6. A `custom-cont-init.d` script handles first-run setup: `argv.json`, Openbox menu entry, and autostart migration.

---

## Building Locally

```bash
git clone https://github.com/runzhliu/docker-antigravity.git
cd docker-antigravity
docker build -t docker-antigravity .
```

---

## Contributing

PRs and issues are welcome. Please open an issue before submitting a large change.

---

## Disclaimer

This image/script is for personal academic research purposes only. Users are responsible for complying with Google's Terms of Service.

---

## License

MIT
