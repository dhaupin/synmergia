#!/bin/bash
# Synmergia Docker Entrypoint
# Starts Xvfb, VNC, noVNC, and Godot (or stays alive for dev)

set -e

echo "═══════════════════════════════════════"
echo " Synmergia Dev Container"
echo "═══════════════════════════════════════"

# Start Xvfb (virtual framebuffer)
echo "[1/4] Starting Xvfb on :99..."
Xvfb :99 -screen 0 1920x1080x24 &
XVFB_PID=$!
sleep 1

# Start VNC server
echo "[2/4] Starting VNC server..."
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw -bg -o /var/log/vnc.log 2>/dev/null || true

# Start noVNC WebSocket proxy
echo "[3/4] Starting noVNC..."
websockify --web=/usr/share/novnc 6080 localhost:5900 &>/dev/null &
sleep 1

# Start Nginx
echo "[4/4] Starting Nginx..."
nginx -g 'daemon off;' &

echo ""
echo "═══════════════════════════════════════"
echo " Services:"
echo "  HTTP:   http://localhost"
echo "  noVNC:  http://localhost:6080/vnc.html"
echo "  VNC:    localhost:5900"
echo "  Godot:  DISPLAY=:99 godot --path /workspace/project/synmergia"
echo "═══════════════════════════════════════"
echo ""

# If GODOT_MODE=run, start Godot; otherwise stay alive
if [ "${GODOT_MODE}" = "run" ]; then
    echo "Starting Godot in headless mode..."
    export DISPLAY=:99
    exec godot --headless --path /workspace/project/synmergia
else
    echo "Container ready. Godot not auto-started."
    echo "Run: DISPLAY=:99 godot --path /workspace/project/synmergia"
    tail -f /dev/null
fi
