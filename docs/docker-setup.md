# Docker Setup for Synmergia

Your own dev VPS.

## Quick Start

```bash
docker compose up --build
open http://localhost:6080/vnc.html
```

## What's Inside

| Tool | Purpose |
|------|---------|
| Godot 4.7.2 | Engine (server + GUI) |
| Xvfb + VNC + noVNC | Browser-accessible GUI |
| Nginx | Web server |
| Julia 1.11 | Scientific computing |
| Go 1.23 | Custom tools |
| Python + FFmpeg | Automation/media |

## Build Options

```bash
# Default: all tools
docker build -t synmergia .

# Skip heavy tools
docker build -t synmergia --build-arg INSTALL_JULIA=false --build-arg INSTALL_GO=false .

# Include Blender (300MB!)
docker build -t synmergia --build-arg INSTALL_BLENDER=true .
```

## Ports

| Port | Service |
|------|---------|
| 80 | HTTP |
| 6080 | noVNC (browser) |
| 5900 | VNC |
| 9000 | WebSocket |

## Usage

```bash
# Run Godot
docker compose run --rm synmergia bash -c "DISPLAY=:99 godot --path /workspace/project/synmergia"

# Run server (headless)
docker compose run --rm synmergia godot --headless --path /workspace/project/synmergia --server

# Screenshot (via VNC browser - recommended)
open http://localhost:6080/vnc.html

# Screenshot via command line
docker exec synmergia bash -c "DISPLAY=:99 ffmpeg -f x11grab -i :99 -vframes 1 -update 1 /workspace/project/synmergia/captures/shot.png"

# Video recording
docker exec synmergia bash -c "DISPLAY=:99 ffmpeg -f x11grab -framerate 30 -i :99 -c:v libx264 /workspace/project/synmergia/captures/gameplay.mp4"

# Note: Xvfb uses software rendering (llvmpipe). For visible screenshots,
# use noVNC browser viewing or connect via VNC client (port 5900).
# See docs/screenshots/video-capture.md for details.
```

## noVNC Browser Access

The noVNC service provides browser-based GUI access:

```bash
# View game in browser
open http://localhost:6080/vnc.html

# Connect button auto-connects to localhost:5900
```

## Captures Directory

All screenshots and videos save to `./captures/`:
```bash
ls ./captures/
# screenshots/  videos/  *.png  *.mp4
```

## Files

- `Dockerfile` - The image (optional components via --build-arg)
- `docker-compose.yml` - Runtime
- `captures/` - Output media
