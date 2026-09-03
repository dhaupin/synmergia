#!/bin/bash
# Synmergia Docker Entrypoint
# Starts Xvfb, VNC, noVNC, and Godot

set -e

echo "Starting Synmergia..."

# Start Xvfb (virtual framebuffer)
echo "Starting Xvfb on :99..."
Xvfb :99 -screen 0 1920x1080x24 &
XVFB_PID=$!

# Wait for Xvfb to be ready
sleep 1

# Start VNC server
echo "Starting VNC server..."
x11vnc -display :99 -forever -shared -rfbport 5900 -bg -o /var/log/vnc.log

# Start noVNC WebSocket proxy
echo "Starting noVNC..."
/usr/share/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080 &

# Wait a bit more
sleep 2

# Start Nginx
echo "Starting Nginx..."
nginx

# Check if we should start Godot
if [ "${GODOT_MODE}" = "prod" ]; then
    echo "Starting Godot in headless mode..."
    exec godot --headless --path /workspace/project/synmergia
else
    echo "Starting Godot with GUI..."
    export DISPLAY=:99
    exec godot --path /workspace/project/synmergia
fi
