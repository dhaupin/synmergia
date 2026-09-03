# Docker Setup for Synmergia

One image. Four modes. Works for dev, prod, and CI.

## Quick Start

```bash
docker compose up --build
open http://localhost:6080/vnc.html
```

## Modes

The image is controlled by the `START_MODE` env var:

| Mode | What it starts | Use case |
|------|---------------|---------|
| `dev` (default) | Xvfb + noVNC + nginx + Godot GUI | Local dev, screenshots |
| `prod` | nginx + Godot headless + postgres + redis | VPS production |
| `headless` | Godot headless only | Bot runner, CI runner |
| `test` | Runs smoke tests, exits | CI pipeline |

## Profiles

```bash
# Dev (default) — GUI in browser
docker compose --profile dev up --build

# Production — headless + DBs
docker compose --profile prod up --build

# Headless runner — Godot only
docker compose --profile headless up --build

# Smoke tests
docker run --rm -e START_MODE=test synmergia
```

## What's Inside

| Tool | Purpose |
|------|---------|
| Godot 4.7.2 | Engine (server + GUI) |
| Xvfb + VNC + noVNC | Browser-accessible GUI (dev only) |
| Nginx | Web server + WebSocket proxy |
| Julia 1.11 | Scientific computing |
| Go 1.23 | Custom tools |
| Chromium + Puppeteer | Screenshot automation |
| Certbot | HTTPS certificate management |
| PostgreSQL + Redis | Data stores (prod only) |

## Ports

| Port | DEV | PROD | Service |
|------|-----|------|---------|
| 80 | ✅ | ✅ | HTTP |
| 443 | ✅ | ✅ | HTTPS (self-signed or Let's Encrypt) |
| 6080 | ✅ | ❌ | noVNC (browser GUI) |
| 5900 | ✅ | ❌ | VNC |
| 9000 | ✅ | ✅ | WebSocket |

## Screenshots

Run inside the container:

```bash
docker exec <container> node /workspace/project/synmergia/synmergia/scripts/screenshot.js \
  --output /workspace/project/synmergia/captures/screenshots/<name>.png \
  --wait 10000
```

Captures land in `./captures/` on the host (bind-mounted).

## HTTPS / Let's Encrypt

The image ships with self-signed certs by default.

For real HTTPS with Let's Encrypt:

```bash
# 1. Get certs (run once)
docker compose --profile prod run --rm certbot

# 2. Uncomment the certbot volume in docker-compose.yml:
#    volumes:
#      - ./certs:/etc/letsencrypt

# 3. Restart
docker compose --profile prod restart synmergia
```

## Environment Variables

```bash
START_MODE=dev|prod|headless   # Which mode to start (default: dev)
GODOT_PORT=9000               # Game WebSocket port
POSTGRES_PASSWORD=...         # Required for prod
JWT_SECRET=...                 # Required for prod
DOMAIN=play.example.com       # For Let's Encrypt
```

## Files

- `Dockerfile` — Unified image (all modes)
- `docker-compose.yml` — Dev + prod profiles
- `docker/entrypoint.sh` — Mode dispatcher
- `nginx.conf` — Reverse proxy config
- `captures/` — Screenshots and videos (host mount)
