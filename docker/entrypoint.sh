#!/bin/bash
# ============================================================================
# Synmergia Container Entrypoint
# Handles all run modes: dev, prod, headless, test
# ============================================================================

set -euo pipefail

START_MODE="${START_MODE:-dev}"

# Ensure capture dirs exist
mkdir -p /workspace/project/synmergia/captures/screenshots
mkdir -p /workspace/project/synmergia/captures/videos

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
    cd /workspace/project/synmergia
    for test_file in synmergia/tests/test_*.gd; do
        [[ -f "$test_file" ]] || continue
        log "  Running: $test_file"
        godot --headless --path /workspace/project/synmergia \
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
    log "Mode: DEV — starting Xvfb + noVNC + nginx + Godot GUI"

    # Xvfb virtual display
    Xvfb :99 -screen 0 1920x1080x24 &
    sleep 1

    # VNC server (optional — bind to localhost to avoid exposure)
    x11vnc -display :99 -forever -shared -rfbport 5900 \
        -nopw -bg -localhost 2>/dev/null || true

    # WebSocket proxy for noVNC
    websockify --web=/usr/share/novnc 6080 localhost:5900 &>/dev/null &

    # Nginx
    _setup_nginx
    nginx -g 'daemon off;' &

    # Godot (with GUI rendering to Xvfb)
    log "Starting Godot (DISPLAY=:99)..."
    DISPLAY=:99 godot --path /workspace/project/synmergia &

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
    log ""
    log "Screenshots:"
    log "  node /workspace/project/synmergia/synmergia/scripts/screenshot.js \\"
    log "    --output /workspace/project/synmergia/captures/screenshots/<name>.png"
    log ""

    tail -f /dev/null
    exit 0
fi

# ── PROD MODE ──────────────────────────────────────────────────────────────
# nginx + Godot headless + optional certbot.
if [[ "$START_MODE" == "prod" ]]; then
    log "Mode: PROD — starting nginx + Godot headless"

    # nginx (HTTP + HTTPS if certs exist)
    _setup_nginx
    nginx -g 'daemon off;' &

    # Godot headless
    log "Starting Godot (headless)..."
    godot --headless --path /workspace/project/synmergia \
        --server-port "${GODOT_PORT:-9000}" &

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

    godot --headless --path /workspace/project/synmergia \
        --server-port "${GODOT_PORT:-9000}" &

    log "Godot headless running on port ${GODOT_PORT:-9000}"
    log "PID: $!"

    tail -f /dev/null
    exit 0
fi

# ── Unknown mode ────────────────────────────────────────────────────────────
log "Unknown START_MODE='$START_MODE'"
log "Valid modes: dev, prod, headless, test"
exit 1
