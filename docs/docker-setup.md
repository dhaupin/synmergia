# Docker Setup for Synmergia

## Quick Start

### Headless Testing (no GUI)
```bash
docker build -f Dockerfile.godot-headless -t synmergia-test .
docker run --rm synmergia-test
```

### GUI Testing with VNC/noVNC
```bash
docker build -f Dockerfile.godot-gui -t synmergia-gui .
docker run --rm -p 6080:6080 -p 5900:5900 synmergia-gui
```

Then open in browser:
- **noVNC**: http://localhost:6080/vnc.html
- **VNC client**: Connect to localhost:5900

### Full Stack (Server + Web + WebSocket + Julia + GUI)
```bash
docker build -f Dockerfile.synmergia-full -t synmergia-full .
docker run --rm -p 80:80 -p 443:443 -p 8080:8080 -p 6080:6080 -p 5900:5900 -p 9000:9000 synmergia-full
```

## Docker Images

| Image | Purpose | Ports |
|-------|---------|-------|
| `synmergia-test` | Headless test runner | - |
| `synmergia-gui` | GUI + VNC/noVNC | 6080, 5900 |
| `synmergia-full` | Complete stack | 80, 443, 8080, 6080, 5900, 9000 |

## What's Included

### Godot 4.7.2
- Standard binary (works for server + GUI)
- Export templates (for HTML5 export)

### Development Tools
- **Julia** 1.11 - Scientific computing
- **Go** 1.23 - WebSocket server / custom tools
- **Python** 3 - Scripts / automation
- **Nginx** - Web server (serve HTML5 export)
- **Xvfb + VNC + noVNC** - GUI preview

### Services
| Port | Service |
|------|---------|
| 80/443 | HTTP/HTTPS (Nginx) |
| 8080 | HTTP (alternate) |
| 6080 | noVNC web interface |
| 5900 | VNC |
| 9000 | WebSocket (Godot ENet) |

## Common Commands

```bash
# Run game server (headless)
docker run --rm synmergia-full godot --headless --path /workspace/project/synmergia --server

# Run game GUI
docker run --rm -p 6080:6080 synmergia-full bash -c "Xvfb :99 & DISPLAY=:99 godot --path /workspace/project/synmergia"

# Run specific test
docker run --rm synmergia-test godot --headless --path /workspace/project/synmergia --script res://tests/test_hud_integration.gd

# Export for HTML5 (on local machine with Godot editor)
godot --headless --export-release "Web" exports/index.html
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile.godot-gui` | GUI with Xvfb + VNC + noVNC |
| `Dockerfile.godot-headless` | Lightweight headless test runner |
| `Dockerfile.synmergia-full` | Complete stack (server + web + GUI) |
| `docker-compose.*.yml` | Compose files for multi-container setups |
| `.dockerignore` | Exclude unnecessary files |

## Requirements

- Docker installed and running
- Full stack: ~4GB RAM recommended
- GUI only: ~2GB RAM
- Headless tests: ~512MB RAM
