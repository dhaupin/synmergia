# Docker Setup for Synmergia

One image. Everything you need.

## Quick Start

```bash
# Build and run
docker compose up --build

# Open in browser
open http://localhost:6080/vnc.html
```

## What's Inside

| Tool | Purpose |
|------|---------|
| Godot 4.7.2 | Engine (server + GUI) |
| Julia 1.11 | Scientific computing |
| Go 1.23 | WebSocket/tools |
| Python 3 + OpenCV | Scripts/automation |
| FFmpeg | Video/streaming |
| ImageMagick | Screenshot |
| Puppeteer | Headless testing |
| Xvfb + VNC + noVNC | GUI preview |
| Nginx | Web server |

## Ports

| Port | Service |
|------|---------|
| 80 | HTTP |
| 5900 | VNC |
| 6080 | noVNC |
| 9000 | WebSocket |

## Usage

```bash
# Run game server (headless)
docker compose run --rm synmergia godot --headless --path /workspace/project/synmergia --server

# Run game GUI
docker compose run --rm synmergia bash -c "DISPLAY=:99 godot --path /workspace/project/synmergia"

# Screenshot
docker exec synmergia bash -c "DISPLAY=:99 scrot /workspace/project/synmergia/captures/shot.png"

# Record video (inside container)
docker exec -it synmergia bash
  DISPLAY=:99 ffmpeg -f x11grab -framerate 30 -i :99 output.mp4

# Run tests
docker compose run --rm synmergia godot --headless --path /workspace/project/synmergia --script res://tests/test_hud_integration.gd
```

## Captures

Screenshots/videos go to `./captures/`:
```
captures/
├── screenshots/
└── videos/
```

Copy out: `docker cp synmergia:/workspace/project/synmergia/captures/screenshots/ .`

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | The image |
| `docker-compose.yml` | Runtime config |
| `tools/docker/scripts/` | Helper scripts |
| `captures/` | Output media |
