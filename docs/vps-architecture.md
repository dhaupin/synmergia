# VPS Architecture

## Overview

Synmergia runs on a VPS with two modes:

| Mode | Purpose | Services |
|------|---------|----------|
| **DEV** | Development | Godot GUI, VNC, noVNC, dev tools |
| **PROD** | Live game server | Godot server, Postgres, Nginx, WebSocket |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         VPS                                 │
│                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐     │
│  │   Nginx      │   │   Godot      │   │   Postgres   │     │
│  │  (reverse    │◄──│  (game       │◄──│   (player   │     │
│  │   proxy)     │   │   server)    │   │   data)     │     │
│  └──────────────┘   └──────────────┘   └──────────────┘     │
│         │                  │                               │
│         │                  │                               │
│  ┌──────┴──────┐   ┌──────┴──────┐                       │
│  │ WebSocket   │   │  Auth/API    │                       │
│  │ (clients)   │   │  (REST)      │                       │
│  └─────────────┘   └─────────────┘                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Ports

| Port | Service | DEV | PROD | Protocol |
|------|---------|-----|------|----------|
| 80 | HTTP (Nginx) | ✅ | ✅ | HTTP |
| 443 | HTTPS | ❌ | ✅ | HTTPS |
| 6080 | noVNC | ✅ | ❌ | WebSocket |
| 5900 | VNC | ✅ | ❌ | VNC |
| 9000 | WebSocket | ✅ | ✅ | WebSocket |
| 3306 | Postgres | ❌ | Internal | TCP |

## Services

### Godot Server
- **DEV**: Full GUI mode with `--display-driver x11`
- **PROD**: Headless mode with `--headless`
- Handles all game logic, entities, combat, world state
- Authoritative server architecture

### Postgres Database
- Player accounts
- Character data
- World state snapshots
- Chat logs
- Guild/faction data

### Nginx
- Reverse proxy
- Static file serving (game client downloads)
- WebSocket forwarding
- SSL termination (PROD)

### Authentication
- JWT-based auth
- Session management
- Account registration/login

## Docker Modes

### DEV Mode
```bash
docker compose up
```
- Full GUI environment
- VNC/noVNC for browser access
- All dev tools (Julia, Go, Blender optional)
- Volume mounts for live editing

### PROD Mode
```bash
docker compose -f docker-compose.prod.yml up -d
```
- Minimal footprint
- No VNC/GUI
- Auto-restart on crash
- Log aggregation

## Environment Variables

```bash
# Server
GODOT_MODE=prod              # dev | prod
GODOT_PORT=9000              # WebSocket port
GODOT_MAX_PLAYERS=100        # Player limit

# Database
POSTGRES_DB=synmergia
POSTGRES_USER=synmergia
POSTGRES_PASSWORD=<secret>

# Auth
JWT_SECRET=<secret>
SESSION_DURATION=86400        # 24 hours

# Network
DOMAIN=play.synmergia.com
SSL_CERT=/certs/fullchain.pem
SSL_KEY=/certs/privkey.pem
```

## Security

- Firewall (AppFirewall in-game)
- Rate limiting on WebSocket
- DDoS protection (upstream)
- Database credentials via secrets
- SSL/TLS in production
- Regular backups

## Backup Strategy

- Database: Daily pg_dump
- Game state: Periodic snapshots
- Off-site: rsync to backup server

## Monitoring

- Server uptime
- Player count
- Memory/CPU usage
- Error rates
- Database connections

## Deployment

```bash
# Build production image
docker build -t synmergia:prod --build-arg DEV_MODE=false .

# Deploy
docker compose -f docker-compose.prod.yml up -d

# Rollback
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

## File Structure

```
synmergia/
├── Dockerfile              # Multi-stage build
├── Dockerfile.prod        # Production only
├── docker-compose.yml     # DEV (default)
├── docker-compose.prod.yml # PROD
├── .env.example           # Environment template
├── certs/                 # SSL certificates (prod)
│   ├── fullchain.pem
│   └── privkey.pem
└── backups/               # Database backups
    └── daily/
```
