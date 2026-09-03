#!/bin/bash
# entrypoint.sh — Start all Synmergia dev services
set -e

echo "================================================"
echo " Synmergia Dev Container"
echo "================================================"

# ---------------------------------------------------------------------------
# Xvfb — virtual framebuffer (required for headless Godot)
# ---------------------------------------------------------------------------
echo "[1/6] Starting Xvfb..."
Xvfb :99 -screen 0 1920x1080x24 &
sleep 1

# ---------------------------------------------------------------------------
# x11vnc — VNC server on top of Xvfb (for noVNC to connect to)
# ---------------------------------------------------------------------------
echo "[2/6] Starting x11vnc..."
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw -bg 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# websockify — WebSocket proxy (noVNC ↔ VNC bridge)
# ---------------------------------------------------------------------------
echo "[3/6] Starting websockify..."
websockify --web=/usr/share/novnc 6080 localhost:5900 &>/dev/null &
sleep 1

# ---------------------------------------------------------------------------
# Nginx — serve static files + proxy WebSocket
# ---------------------------------------------------------------------------
echo "[4/6] Starting nginx..."
nginx -g 'daemon off;' &
sleep 1

# ---------------------------------------------------------------------------
# Godot game server
# Modes:
#   START_GODOT=0         skip entirely
#   START_GODOT=headless  --headless (no rendering, for servers)
#   anything else         normal (renders to Xvfb, needed for noVNC screenshots)
# ---------------------------------------------------------------------------
if [[ "${START_GODOT:-normal}" == "0" ]]; then
    echo "[5/6] Skipping Godot (START_GODOT=0)"
elif [[ "${START_GODOT}" == "headless" ]]; then
    echo "[5/6] Starting Godot (headless mode)..."
    mkdir -p /var/lib/synmergia
    DISPLAY=:99 godot --headless --path /workspace/project/synmergia &
    sleep 2
else
    echo "[5/6] Starting Godot (normal, renders to Xvfb)..."
    mkdir -p /var/lib/synmergia
    DISPLAY=:99 godot --path /workspace/project/synmergia &
    sleep 3
fi

# ---------------------------------------------------------------------------
# Ensure captures dir exists for screenshot output
# ---------------------------------------------------------------------------
mkdir -p /workspace/project/synmergia/captures/screenshots

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================================"
echo " Services"
echo "================================================"
echo " HTTP:    http://localhost          (nginx, static files)"
echo " noVNC:   http://localhost:6080/vnc.html"
echo " VNC:     localhost:5900"
echo " Godot:   DISPLAY=:99 godot --path /workspace/project/synmergia"
echo ""
echo " For screenshots: node /workspace/project/synmergia/synmergia/scripts/screenshot.js"
echo "================================================"

# Keep container alive — logs from background processes still stream to stdout
tail -f /dev/null
