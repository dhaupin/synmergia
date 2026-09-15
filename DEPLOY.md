# Synmergia — Deployment Guide

> **Status:** v1 — Development/Staging ready. Production guidance marked where applicable.
> **Last updated:** 2026-09-15

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Architecture Overview](#2-architecture-overview)
3. [Development Setup](#3-development-setup)
4. [Staging/Production Setup](#4-stagingproduction-setup)
5. [Docker Reference](#5-docker-reference)
6. [Environment Configuration](#6-environment-configuration)
7. [Database Setup](#7-database-setup)
8. [Web Server (nginx)](#8-web-server-nginx)
9. [SSL/TLS](#9-ssltls)
10. [Monitoring & Health](#10-monitoring--health)
11. [Backup & Restore](#11-backup--restore)
12. [Scaling Considerations](#12-scaling-considerations)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Quick Start

### Prerequisites
- Docker & Docker Compose v2
- 4GB RAM minimum (8GB recommended)
- Ports 80, 443, 6080, 9000 available

### Start Development Server

```bash
# Clone the repository
git clone https://github.com/dhaupin/synmergia.git
cd synmergia

# Start in development mode (default)
docker compose up --build

# Access via browser
open http://localhost:6080/vnc.html  # VNC viewer
open http://localhost                # HTTP (if nginx running)
```

### Start Production Server

```bash
# Clone and create .env file (see Environment Variables section for full list)
git clone https://github.com/dhaupin/synmergia.git
cd synmergia
cat > .env << 'EOF'
START_MODE=prod
POSTGRES_PASSWORD=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 64)
DOMAIN=play.example.com
CERT_EMAIL=admin@example.com
EOF

# Start with PostgreSQL and Redis
docker compose --profile prod up --build -d

# Get Let's Encrypt certificates (first time)
docker compose --profile prod run --rm certbot
```

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Compose                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌────────────────────────┐  │
│  │   nginx     │  │   Godot     │  │   Supporting Services  │  │
│  │  (reverse   │  │  (headless  │  │  ┌──────────┐ ┌─────┐ │  │
│  │   proxy)    │  │   server)   │  │  │PostgreSQL│ │Redis│ │  │
│  │             │  │             │  │  │  :5432   │ │:6379│ │  │
│  │  :80 :443   │  │  :9000     │  │  └──────────┘ └─────┘ │  │
│  └──────┬──────┘  └──────┬──────┘  └────────────────────────┘  │
│         │                 │                                      │
│         └────────┬────────┘                                      │
│                  ▼                                                │
│         ┌───────────────┐                                        │
│         │  Game Client  │                                        │
│         │  (Browser)    │                                        │
│         └───────────────┘                                        │
└─────────────────────────────────────────────────────────────────┘
```

### Service Breakdown

| Service | Port | Purpose | Profile |
|---------|------|---------|---------|
| nginx | 80, 443 | Reverse proxy, static files | dev, prod |
| noVNC | 6080 | Browser VNC (dev only) | dev |
| Godot | 9000 | Game server | all |
| PostgreSQL | 5432 | Persistent storage | dev, prod |
| Redis | 6379 | Cache, sessions | dev, prod |

### Container Modes

| Mode | Use Case | Components |
|------|----------|------------|
| `dev` | Local development | Xvfb + noVNC + nginx + Godot GUI |
| `prod` | Staging/Production | nginx + Godot headless + postgres + redis |
| `headless` | CI/Bot runners | Godot headless only |
| `test` | Smoke tests | Runs test suite and exits |

---

## 2a. Bridge Sidecars

The Godot client never talks to PostgreSQL or Redis directly. Instead it
hits two local HTTP sidecars that live inside the main container:

| Sidecar | Port | Backends | Purpose |
|---------|------|----------|---------|
| `pg-bridge` | 8080 | sqlite, postgres | Persistence (accounts, inventory, etc.) |
| `redis-bridge` | 8081 | inmemory, redis | Cache / sessions / rate-limit state |

Both sidecars are stdlib-only by default (sqlite + inmemory). They lazily
import `psycopg2-binary` or `redis-py` only when the matching backend is
selected via env. This keeps the base image small and the sidecars usable
for local dev without external services.

### Wire Protocol

The Godot adapters (`game/adapters/persistence/`, `game/adapters/cache/`)
implement the HTTP contract these sidecars expose. The full protocol spec
lives in `labs/prd-db.md` sec.3-5 (persistence) and sec.7.2 (cache).

### Health

    curl -f http://localhost:8080/health   # pg-bridge
    curl -f http://localhost:8081/health   # redis-bridge

## 3. Development Setup

### Local Development with Docker

```bash
# Start all services
docker compose up --build

# Start with PostgreSQL and Redis
docker compose --profile dev up --build

# View logs
docker compose logs -f synmergia

# Run shell in container
docker compose exec synmergia bash
```

### Local Development without Docker

```bash
# Install Godot 4.7.2
# Download from: https://github.com/godotengine/godot/releases/tag/4.7.2-stable

# Open project in Godot editor
godot --editor game/

# Or run headless server
godot --headless --path game/

# Run smoke tests (inside the game/ directory)
cd game
for test in tests/test_*.gd; do
    godot --headless --path . --script "res://$test"
done
```

### Environment Variables (Development)

Create a `.env` file:

```bash
# Game Server
START_MODE=dev
GODOT_PORT=9000

# Database
POSTGRES_PASSWORD=synmergia_dev_pass
POSTGRES_HOST=localhost

# Redis
REDIS_HOST=localhost
REDIS_ENABLED=true

# Security
JWT_SECRET=dev_jwt_secret_change_in_production
```

---

## 4. Staging/Production Setup

### Prerequisites

1. **Server Requirements**
   - 4+ CPU cores
   - 8GB+ RAM
   - 50GB+ storage
   - Ubuntu 22.04 LTS (recommended)

2. **Domain Setup**
   - DNS A record pointing to server IP
   - SSL certificate (Let's Encrypt or purchased)

### Installation Steps

#### 1. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```

#### 2. Clone and Configure

```bash
git clone https://github.com/dhaupin/synmergia.git
cd synmergia

# Create production environment file
cat > .env << 'EOF'
START_MODE=prod
GODOT_PORT=9000

# Generate secure password for PostgreSQL
POSTGRES_PASSWORD=$(openssl rand -base64 32)

# JWT Secret - generate a strong random string
JWT_SECRET=$(openssl rand -base64 64)

# Domain
DOMAIN=play.example.com
CERT_EMAIL=admin@example.com

# Redis (no password in current setup)
REDIS_HOST=redis
REDIS_ENABLED=true
EOF

# Secure the .env file
chmod 600 .env
```

#### 3. Firewall Configuration

```bash
# UFW example
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp     # HTTP
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 9000/tcp   # Godot (restrict in production)
sudo ufw enable
```

#### 4. Obtain SSL Certificates

```bash
# Start services temporarily
docker compose --profile prod up -d postgres redis

# Wait for PostgreSQL to be ready
sleep 10

# Get Let's Encrypt certificate
docker compose --profile prod run --rm certbot

# Restart with HTTPS
docker compose --profile prod up -d
```

#### 5. Systemd Service (Optional)

For production, create a systemd service. Adjust paths as needed for your installation:

```bash
# Create the service file
sudo cat > /etc/systemd/system/synmergia.service << 'EOF'
[Unit]
Description=Synmergia MMORPG Server
Requires=docker.service
After=network-online.target docker.service
Wants=postgresql.service redis.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/path/to/synmergia  # Change to your installation path
ExecStartPre=-/usr/bin/docker compose -f /path/to/synmergia/docker-compose.yml stop
ExecStart=/usr/bin/docker compose --profile prod up -d
ExecStop=/usr/bin/docker compose --profile prod down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable synmergia
sudo systemctl start synmergia
sudo systemctl status synmergia
```

---

## 5. Docker Reference

### Build

```bash
# Build the image
docker build -t synmergia .

# Build with custom Godot version
docker build --build-arg GODOT_VERSION=4.7.2 -t synmergia:4.7.2 .
```

### Run

```bash
# Development (all services)
docker compose up

# Production (with postgres/redis)
docker compose --profile prod up -d

# Headless (server only)
docker compose --profile headless up -d

# Specific service
docker compose up -d synmergia
```

### Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f synmergia
docker compose logs -f postgres
docker compose logs -f redis

# Last 100 lines
docker compose logs --tail 100 synmergia
```

### Volumes

| Volume | Purpose |
|--------|---------|
| `synmergia_synmergia-data` | Game data (`/var/lib/synmergia`) |
| `synmergia_postgres-data` | PostgreSQL database |
| `synmergia_redis-data` | Redis cache |
| `synmergia_nginx-html` | Let's Encrypt webroot |

To list volumes: `docker volume ls | grep synmergia`
To inspect a volume: `docker volume inspect synmergia_postgres-data`

### Ports

| Port | Service | Notes |
|------|---------|-------|
| 80 | nginx | HTTP |
| 443 | nginx | HTTPS |
| 6080 | noVNC | Dev VNC viewer |
| 5900 | x11vnc | VNC server |
| 9000 | Godot | Game server |

---

## 6. Environment Configuration

### Environment Variables

| Variable | Default | Description | Required |
|----------|---------|-------------|----------|
| `START_MODE` | `dev` | Run mode: dev, prod, headless, test | Yes |
| `GODOT_PORT` | `9000` | Godot server port | No |
| `GODOT_UPSTREAM` | `synmergia:9000` | Godot upstream for nginx | No |
| `POSTGRES_PASSWORD` | `synmergia_dev_pass` | PostgreSQL password | **Yes** |
| `POSTGRES_HOST` | `postgres` | PostgreSQL host | No |
| `REDIS_HOST` | `redis` | Redis host | No |
| `REDIS_ENABLED` | `true` | Enable Redis | No |
| `JWT_SECRET` | `change_me_in_production` | JWT signing secret | **Yes** |
| `DOMAIN` | `localhost` | Domain for SSL certs | For production |
| `CERT_EMAIL` | `admin@localhost` | Email for Let's Encrypt | For production |

### Runtime Mode Detection

The Godot server detects mode via `START_MODE`:

```bash
START_MODE=dev    # Xvfb + GUI (requires display)
START_MODE=prod   # Headless + nginx
START_MODE=headless  # Headless only, no nginx
START_MODE=test   # Run tests and exit
```

---

## 7. Database Setup

The app never connects to Postgres directly. All persistence goes through
`pg-bridge` (port 8080), which exposes a thin HTTP API over SQLite
(default) or Postgres. See section 2a for the full bridge overview.

### PostgreSQL

**Version:** 16-alpine

**Initial Schema:** Auto-created on first run.

**Connection:**
```
Host: postgres
Port: 5432
Database: synmergia
User: synmergia
Password: (from POSTGRES_PASSWORD)
```

**Health Check:**
```bash
docker compose exec postgres pg_isready -U synmergia
```

**Connect to Database:**
```bash
docker compose exec postgres psql -U synmergia synmergia
```

### Redis

The app never connects to Redis directly. All cache operations go through
`redis-bridge` (port 8081), which exposes a thin HTTP API over an
in-memory backend (default) or Redis. See section 2a for the full bridge
overview.

**Version:** 7-alpine

**Configuration:**
- Persistence: AOF enabled
- Max Memory: 256MB
- Eviction Policy: allkeys-lru

**Connection:**
```
Host: redis
Port: 6379
```

**Health Check:**
```bash
docker compose exec redis redis-cli ping
```

---

## 8. Web Server (nginx)

### Configuration Location
- Container: `/etc/nginx/nginx.conf`
- Host: `nginx.conf` in repo root

### Key Routes

| Path | Destination | Notes |
|------|------------|-------|
| `/` | Static files | index.html |
| `/client/` | Game client files | 1-day cache |
| `/assets/` | Game assets | 7-day cache |
| `/api/auth/*` | Godot auth API | Rate limited |
| `/api/account/*` | Account API | Rate limited |
| `/game/*` | Game API | Rate limited |
| `/ws/*` | WebSocket | Upgrade header |
| `/admin/*` | Admin API | Rate limited |

### Rate Limiting

| Zone | Rate | Burst |
|------|------|-------|
| `api` | 10r/s | 50 |
| `login` | 1r/s | - |

### Custom Configuration

To use custom nginx configuration:

```bash
# Copy custom config
cp custom-nginx.conf nginx.conf

# Rebuild and restart
docker compose --profile prod up --build -d
```

---

## 9. SSL/TLS

### Development (Self-Signed)

Automatically generated on container build:
- Certificate: `/etc/nginx/ssl/nginx.crt`
- Key: `/etc/nginx/ssl/nginx.key`

Browser will show security warning. Accept to proceed.

### Production (Let's Encrypt)

```bash
# 1. Start services (without nginx initially)
docker compose --profile prod up -d postgres redis

# 2. Get certificate
docker compose --profile prod run --rm certbot

# 3. Restart with HTTPS
docker compose --profile prod up -d
```

### Manual Certificate Upload

```bash
# Mount certificates directory
# In docker-compose.yml or .env:
# volumes:
#   - ./srv/certs:/etc/letsencrypt:ro

# Structure:
srv/certs/
└── live/
    └── play.example.com/
        ├── fullchain.pem
        └── privkey.pem
```

---

## 10. Monitoring & Health

### Health Endpoints

| Endpoint | Service | Response |
|----------|---------|----------|
| `http://localhost/` | nginx | 200 OK |
| `http://localhost/health` | nginx | "OK" text |
| `:5432` | PostgreSQL | pg_isready |
| `:6379` | Redis | PONG |

### Docker Health Checks

```bash
# View container health
docker compose ps

# Inspect health status
docker inspect synmergia | jq '.[0].State.Health'
```

### Logs

```bash
# Application logs
docker compose logs synmergia

# PostgreSQL logs
docker compose logs postgres

# nginx access logs
docker compose exec nginx tail -f /var/log/nginx/access.log

# nginx error logs
docker compose exec nginx tail -f /var/log/nginx/error.log
```

### Useful Commands

```bash
# Resource usage
docker stats

# Container process
docker compose top synmergia

# Network connections
docker compose exec synmergia netstat -tlnp
```

---

## 11. Backup & Restore

### Database Backup

```bash
# Backup PostgreSQL (use -T for non-interactive/piped input)
docker compose exec -T postgres pg_dump -U synmergia synmergia > backup_$(date +%Y%m%d).sql

# Backup with compression
docker compose exec -T postgres pg_dump -U synmergia synmergia | gzip > backup_$(date +%Y%m%d).sql.gz
```

### Database Restore

```bash
# Stop game server
docker compose stop synmergia

# Restore database
docker compose exec -T postgres psql -U synmergia synmergia < backup_20240101.sql

# Start game server
docker compose start synmergia
```

### Volume Backup

```bash
# Get volume names
POSTGRES_VOLUME=$(docker volume ls -q | grep postgres-data)
REDIS_VOLUME=$(docker volume ls -q | grep redis-data)
SYNMERGIA_VOLUME=$(docker volume ls -q | grep synmergia-data)

# Backup volumes
docker compose stop
sudo tar -czf synmergia_backup_$(date +%Y%m%d).tar.gz \
    /var/lib/docker/volumes/$POSTGRES_VOLUME \
    /var/lib/docker/volumes/$REDIS_VOLUME \
    /var/lib/docker/volumes/$SYNMERGIA_VOLUME
docker compose start
```

### Scheduled Backups

Add to crontab:

```bash
# Daily database backup at 3 AM (use -T for non-interactive)
0 3 * * * docker compose exec -T postgres pg_dump -U synmergia synmergia | gzip > /backups/synmergia_$(date +\%Y\%m\%d).sql.gz

# Keep last 7 days
0 4 * * * find /backups -name "synmergia_*.sql.gz" -mtime +7 -delete
```

### WorldManifest Disaster Recovery (3-Tier Seed Storage)

The Synmergia `WorldManifest` contains the authoritative root seeds and world-level configuration. It uses a dedicated 3-tier disaster recovery architecture managed by scripts in `srv/backup/`:

1. **Tier 1 (Operational)**: PostgreSQL `world_manifest` table with read replica.
2. **Tier 2 (Hot Tier)**: Daily `.json.gz` snapshots with SHA-256 checksums uploaded to S3 at `03:00 UTC`.
3. **Tier 3 (Cold Tier)**: Snapshots older than 7 days migrated to cold storage / Glacier; 30-day retention purge.

#### Commands

```bash
# Run manual backup and upload
./srv/backup/manifest.sh --backup

# Check backup status and audit log
./srv/backup/manifest.sh --status

# Restore WorldManifest from snapshot (verifies SHA-256 before restoration)
./srv/backup/manifest.sh --restore --from 2026-09-15
```

> **Disaster Recovery Note:** Restoring WorldManifest from a snapshot rewinds the world seed-state tree to that date. All player state created prior to that date will be restored to that snapshot's state. See `srv/backup/README.md` for full details.

---

## 12. Scaling Considerations

### Horizontal Scaling (Future)

Current architecture is single-shard. For horizontal scaling:

1. **Multiple Shard Containers**
   - Run multiple `synmergia` containers
   - Each with unique `SHARD_ID`
   - Load balancer in front

2. **Shared State**
   - PostgreSQL supports connection pooling
   - Redis Cluster for cache distribution
   - Coordinator service for cross-shard communication

3. **Load Balancer**
   ```nginx
   upstream synmergia_shards {
       server shard1:9000;
       server shard2:9000;
       server shard3:9000;
   }
   ```

### Vertical Scaling

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Storage | 20 GB | 50+ GB |

### Database Optimization

For Docker Compose with the PostgreSQL image, create a custom configuration:

```bash
# Create postgresql.conf
echo "max_connections = 100
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 128MB
wal_buffers = 16MB
checkpoint_completion_target = 0.9" > postgres.conf
```

Then mount it in docker-compose.yml:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
    volumes:
      - ./postgres.conf:/etc/postgresql/postgresql.conf:ro
```

> **Note:** Values above are conservative for a single-server setup. Adjust based on available RAM (shared_buffers = 25% of RAM is a common starting point).

---

## 13. Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs synmergia

# Check ports
sudo netstat -tlnp | grep -E '(80|443|9000)'

# Restart services
docker compose restart synmergia
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker compose ps postgres

# Test connection
docker compose exec synmergia bash -c 'PGPASSWORD=$POSTGRES_PASSWORD psql -h postgres -U synmergia -d synmergia -c "SELECT 1"'
```

### Performance Issues

```bash
# Check resource usage
docker stats --no-stream

# Check Godot memory
docker compose exec synmergia cat /proc/meminfo | grep -E 'MemTotal|MemAvailable'

# Profile Godot
docker compose exec synmergia godot --headless --path /workspace/project/game --profile
```

### Data Corruption

```bash
# Stop all services
docker compose stop

# Verify PostgreSQL data integrity
docker compose exec postgres psql -U synmergia -d synmergia -c "SELECT 1"

# Check PostgreSQL logs for corruption
docker compose logs postgres | grep -i error

# Rebuild from backup
# See Backup & Restore section
```

### WebSocket Connection Issues

```bash
# Check nginx WebSocket support
docker compose exec nginx nginx -V 2>&1 | grep -i proxy

# Test WebSocket endpoint
wscat -c ws://localhost:9000

# Check nginx logs
docker compose logs --tail 100 nginx | grep -i websocket
```

### Common Error Messages

| Error | Solution |
|-------|----------|
| `address already in use` | Stop other service on port or change `GODOT_PORT` |
| `connection refused` | Check PostgreSQL/Redis are running: `docker compose ps` |
| `SSL handshake failed` | Install valid SSL certificate or accept self-signed |
| `permission denied` | Check volume permissions: `sudo chown -R $(id -u):$(id -g) ./game ./labs` |

---

## 14. Web Portal, Godot WASM & CI/CD Pipeline

Synmergia includes an integrated web client portal with dual-client hosting, static data bridging, and a zero-waste CI pipeline designed specifically to protect GitHub Actions free quotas.

### Architecture

```
Client Browser
 ├── Portal Header (mode switcher)
 ├── React 2D Canvas Client (fast companion & exploration)
 ├── Godot 4.7.2 WASM Client (/web) -> connects via WebSocket (port 9000)
 └── Admin & GM Dashboard (live sidecars: srv/pg-bridge, srv/redis-bridge)
```

### 1. Mandatory Isolation Headers (COOP / COEP)
Godot 4.7.2 WebAssembly requires `SharedArrayBuffer` for multithreading. Any server hosting `/web` must provide:
```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```
In local Vite development and production reverse proxy (`vite.config.ts` and Nginx), these headers are configured automatically.

### 2. Static Data Bridge Synchronization
Static game definitions (classes, species, items, quests, zones) defined in Godot `.tres` resources are synced into the Web Portal with:
```bash
npm run sync:data
```
This executes `scripts/sync_godot_data.ts`, generating `src/data/godot_data.json` without requiring runtime Godot dependencies.

### 3. Packaging the Web PCK
To build the game asset package for the WASM client:
```bash
# Direct packaging with Godot 4.7.2
./scripts/pack_web.sh

# Or via Docker:
docker compose run --rm synmergia godot --headless --path /workspace/project/game --export-pack "Web" /workspace/project/web/game.pck
```

### 4. Zero-Waste GitHub Actions CI (`.github/workflows/web-ci.yml`)
To guarantee you do not exhaust the monthly 2,000 GitHub Actions free minutes:
- **Automatic Run Cancellation**: Any ongoing CI run on the same branch is automatically cancelled immediately when a new commit is pushed (`concurrency: cancel-in-progress: true` + `styfle/cancel-workflow-action`).
- **Strict Path Filtering**: Only changes to `game/**` trigger the workflow. Commits touching markdown (`**.md`), documentation (`docs/**`), research notes (`labs/**`), web files (`src/**`, `web/**`), or scripts are ignored by CI.
- **Standalone Binary Caching**: Uses a lightweight 50MB standalone Godot 4.7.2 headless binary cached across runs instead of pulling multi-gigabyte Docker images. Total CI run duration is ~35–45 seconds.
- **Selective Testing**: Commits run fast GDScript syntax audits and PCK packaging. The full 37-script test suite is restricted to manual `workflow_dispatch` triggers (`run_full_suite: true`).

---

## Quick Reference

```bash
# Start dev server
docker compose up

# Start production server
docker compose --profile prod up -d

# Stop all services
docker compose down

# View status
docker compose ps

# View logs
docker compose logs -f

# Run tests
docker run --rm -e START_MODE=test synmergia

# Shell into container
docker compose exec synmergia bash

# Restart game server
docker compose restart synmergia

# Backup database (use -T for non-interactive)
docker compose exec -T postgres pg_dump -U synmergia synmergia > backup.sql

# Update to latest
git pull && docker compose --profile prod up --build -d
```

---

*For technical architecture details, see [labs/README.md](./labs/README.md).*
*For game development, see [AGENTS.md](./AGENTS.md).*
