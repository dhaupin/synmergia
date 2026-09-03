# Docker Setup for Synmergia

## Quick Start

### Prerequisites
- Copy Godot binary to `bin/godot`:
  ```bash
  mkdir -p bin && cp /path/to/Godot_v4.7.2-stable_linux.x86_64 bin/godot
  ```

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

### Run Specific Test
```bash
docker run --rm synmergia-test godot --headless --path /workspace/project/synmergia --script res://tests/test_hud_integration.gd
```

## Files

| File | Purpose |
|------|---------|
| `Dockerfile.godot-gui` | Full GUI with Xvfb + VNC + noVNC |
| `Dockerfile.godot-headless` | Lightweight headless test runner |
| `docker-compose.godot-gui.yml` | Compose file for GUI testing |
| `.dockerignore` | Exclude unnecessary files from build |

## Requirements

- Docker installed and running
- For GUI: ~2GB RAM recommended
- For headless tests: ~512MB RAM sufficient
