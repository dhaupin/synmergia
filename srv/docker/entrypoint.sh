#!/bin/bash
# ============================================================================
# Synmergia Container Entrypoint
# Handles all run modes: dev, prod, headless, test
# ============================================================================

set -euo pipefail

START_MODE="${START_MODE:-dev}"

# Ensure capture dirs exist
mkdir -p /workspace/project/game/captures/screenshots
mkdir -p /workspace/project/game/captures/videos

log() { echo "[entrypoint] $*"; }

# ── Template nginx.conf ────────────────────────────────────────────────────
# Replace GODOT_UPSTREAM placeholder with the actual value.
# Also configure SSL certs: Let's Encrypt if available, else self-signed.
_setup_nginx() {
    local upstream="${GODOT_UPSTREAM:-localhost:9000}"
    if grep -q "GODOT_UPSTREAM" /etc/nginx/nginx.conf 2>/dev/null; then
        sed -i "s|GODOT_UPSTREAM|${upstream}|g" /etc/nginx/nginx.conf
        log "nginx upstream: $upstream"
    fi

    # SSL certs: prefer Let's Encrypt, fall back to self-signed
    local le_cert="/etc/letsencrypt/live/localhost/fullchain.pem"
    if [[ -f "$le_cert" ]]; then
        log "SSL: using Let's Encrypt certs"
    else
        log "SSL: using self-signed certs"
        sed -i "s|ssl_certificate /etc/letsencrypt/live/localhost/fullchain.pem;|ssl_certificate /etc/nginx/ssl/nginx.crt;|g" \
            /etc/nginx/nginx.conf
        sed -i "s|ssl_certificate_key /etc/letsencrypt/live/localhost/privkey.pem;|ssl_certificate_key /etc/nginx/ssl/nginx.key;|g" \
            /etc/nginx/nginx.conf
    fi
}

# ── TEST MODE ──────────────────────────────────────────────────────────────
# Run smoke tests then exit. Used by CI.
if [[ "$START_MODE" == "test" ]]; then
    log "Mode: TEST — running smoke tests"

    # Start the adapter sidecars in-memory so the adapter tests + any
    # Godot smoke test that touches the registry can talk to a real
    # bridge. InMemory backends are stdlib-only and exit 0 on shutdown.
    PG_BACKEND="${PG_BACKEND:-sqlite}" \
    REDIS_BACKEND="${REDIS_BACKEND:-inmemory}" \
    python3 /workspace/project/srv/pg-bridge/main.py &
    PG_BRIDGE_PID=$!
    python3 /workspace/project/srv/redis-bridge/main.py &
    REDIS_BRIDGE_PID=$!
    # Give the sidecars a moment to bind their ports.
    sleep 1
    log "pg-bridge pid=$PG_BRIDGE_PID  redis-bridge pid=$REDIS_BRIDGE_PID"

    cleanup_bridges() {
        kill "$PG_BRIDGE_PID" 2>/dev/null || true
        kill "$REDIS_BRIDGE_PID" 2>/dev/null || true
        wait "$PG_BRIDGE_PID" 2>/dev/null || true
        wait "$REDIS_BRIDGE_PID" 2>/dev/null || true
    }
    trap cleanup_bridges EXIT

    # Sidecar unit tests (stdlib-only; no Godot needed).
    log "Running pg-bridge tests..."
    python3 /workspace/project/srv/pg-bridge/test_pg_bridge.py >/tmp/pg-bridge-test.log 2>&1 || {
        log "FAIL: pg-bridge tests"; tail -n 30 /tmp/pg-bridge-test.log; exit 1
    }
    log "Running redis-bridge tests..."
    python3 /workspace/project/srv/redis-bridge/test_redis_bridge.py >/tmp/redis-bridge-test.log 2>&1 || {
        log "FAIL: redis-bridge tests"; tail -n 30 /tmp/redis-bridge-test.log; exit 1
    }

    # Godot smoke tests.
    cd /workspace/project/game
    for test_file in game/tests/test_*.gd; do
        [[ -f "$test_file" ]] || continue
        log "  Running: $test_file"
        godot --headless --path /workspace/project/game \
            --script "res://$(basename "$test_file")" || {
            log "FAIL: $test_file"
            exit 1
        }
    done
    log "All smoke tests passed"
    exit 0
fi

# ── DEV MODE ───────────────────────────────────────────────────────────────
# Start Xvfb, x11vnc, websockify, nginx, then Godot GUI.
if [[ "$START_MODE" == "dev" ]]; then
    # Clean up stale lock files from previous runs
    rm -f /tmp/.X99-lock /tmp/.X0-lock
    log "Mode: DEV — starting Xvfb + noVNC + nginx + Godot GUI"

    # Xvfb virtual display
    Xvfb :99 -screen 0 1920x1080x24 &
    sleep 1

    # Window manager — required for X11 input focus with noVNC/x11vnc
    xfwm4 --display :99 2>/dev/null &

    # VNC server — bind to all interfaces so Docker port-forwarding works
    x11vnc -display :99 -forever -shared -rfbport 5900 -nopw -bg

    # WebSocket proxy for noVNC
    websockify --web=/usr/share/novnc 6080 localhost:5900 &>/dev/null &

    # Nginx
    _setup_nginx
    nginx -g 'daemon off;' &

    # Godot (with GUI rendering to Xvfb, software OpenGL)
    log "Starting Godot (DISPLAY=:99, software OpenGL)..."
    sleep 2
    nohup env DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path /workspace/project/game --width 1920 --height 1080 --rendering-driver opengl3 > /tmp/godot.log 2>&1 &

    log ""
    log "============================================"
    log " Synmergia — DEV mode"
    log "============================================"
    log " noVNC:  http://localhost:6080/vnc.html"
    log " VNC:    localhost:5900"
    log " HTTP:   http://localhost"
    log " WS:     ws://localhost:9000"
    log " Mode:   GUI rendered via Xvfb"
    log "============================================"
    log "Screenshots:"
    log "  Press PrintScreen in-game to capture a screenshot"
    log "  Saves to: /workspace/project/game/captures/screenshots/"

    tail -f /dev/null
    exit 0
fi

# ── PROD MODE ──────────────────────────────────────────────────────────────
# nginx + Godot headless + optional certbot.
if [[ "$START_MODE" == "prod" ]]; then
    log "Mode: PROD — starting nginx + Godot headless"

    # Start pg-bridge and redis-bridge sidecars as background processes.
    # These are Python services already installed in the Docker image.
    log "Starting pg-bridge..."
    PG_BACKEND="${PG_BACKEND:-sqlite}" \
    PG_BRIDGE_HOST="127.0.0.1" PG_BRIDGE_PORT="8080" \
    python3 /workspace/project/srv/pg-bridge/main.py &
    PG_BRIDGE_PID=$!

    log "Starting redis-bridge..."
    REDIS_BACKEND="${REDIS_BACKEND:-inmemory}" \
    REDIS_BRIDGE_HOST="127.0.0.1" REDIS_BRIDGE_PORT="8081" \
    python3 /workspace/project/srv/redis-bridge/main.py &
    REDIS_BRIDGE_PID=$!

    # Give the sidecars a moment to bind their ports.
    sleep 1
    log "pg-bridge pid=$PG_BRIDGE_PID  redis-bridge pid=$REDIS_BRIDGE_PID"

    # nginx (HTTP + HTTPS if certs exist)
    _setup_nginx
    nginx -g 'daemon off;' &

    # Godot headless (server auto-starts via START_MODE env var)
    log "Starting Godot (headless)..."
    godot --headless --path /workspace/project/game &

    log ""
    log "============================================"
    log " Synmergia — PROD mode"
    log "============================================"
    log " HTTP:   http://localhost"
    log " WS:     ws://localhost:${GODOT_PORT:-9000}"
    log " HTTPS:  https://localhost (self-signed)"
    log " Mode:   headless (no GUI)"
    log ""
    log "Optional — get real HTTPS certs:"
    log "  certbot certonly --nginx -d yourdomain.com"
    log "============================================"
    log ""

    tail -f /dev/null
    exit 0
fi

# ── HEADLESS MODE ─────────────────────────────────────────────────────────
# Godot headless only — no nginx, no VNC. Good for CI runners, bots.
if [[ "$START_MODE" == "headless" ]]; then
    log "Mode: HEADLESS — Godot headless only"

    godot --headless --path /workspace/project/game &

    log "Godot headless running on port ${GODOT_PORT:-9000}"
    log "PID: $!"

    tail -f /dev/null
    exit 0
fi

# ── TEST MODE ──────────────────────────────────────────────────────────────
# Headless syntax validation and unit check for local docker testing
if [[ "$START_MODE" == "test" ]]; then
    log "Mode: TEST — running Godot headless check"
    godot --headless --path /workspace/project/game --check-only
    log "Validation complete."
    exit 0
fi

# ── Unknown mode ────────────────────────────────────────────────────────────
log "Unknown START_MODE='$START_MODE'"
log "Valid modes: dev, prod, headless, test"
exit 1
