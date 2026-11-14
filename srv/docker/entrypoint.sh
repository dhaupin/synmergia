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

# ── Shared-state sidecars ──────────────────────────────────────────────────
# The engine talks to these over HTTP on 127.0.0.1:8080/8081. They read
# PG_BACKEND / REDIS_BACKEND (sqlite|postgres, inmemory|redis) plus the
# POSTGRES_* / REDIS_* connection env. Defaults stay sqlite/inmemory so a
# single-node dev/CI boot is unchanged; a shard mesh sets the backends to
# postgres/redis and points POSTGRES_HOST/REDIS_HOST at the shared services.
_start_state_bridges() {
    log "Starting pg-bridge (PG_BACKEND=${PG_BACKEND:-sqlite})..."
    PG_BACKEND="${PG_BACKEND:-sqlite}" \
    PG_BRIDGE_HOST="127.0.0.1" PG_BRIDGE_PORT="8080" \
    python3 /workspace/project/srv/pg-bridge/main.py &
    PG_BRIDGE_PID=$!

    log "Starting redis-bridge (REDIS_BACKEND=${REDIS_BACKEND:-inmemory})..."
    REDIS_BACKEND="${REDIS_BACKEND:-inmemory}" \
    REDIS_BRIDGE_HOST="127.0.0.1" REDIS_BRIDGE_PORT="8081" \
    python3 /workspace/project/srv/redis-bridge/main.py &
    REDIS_BRIDGE_PID=$!

    sleep 1
    log "pg-bridge pid=$PG_BRIDGE_PID  redis-bridge pid=$REDIS_BRIDGE_PID"
}

# ── Julia multi-iso orchestrator sidecar ───────────────────────────────────
# The engine's MultiIsoService mirrors the entity roster into this sidecar
# (register -> query_spatial/intersect). It is the stdlib-only server
# (server_lite.jl) on 127.0.0.1:8090 -- deliberately NOT 8080/8081, which
# are pg-bridge/redis-bridge. Fails soft: if julia is absent or the sidecar
# dies, the engine degrades to empty results (no boot failure).
_start_julia_bridge() {
    local script="/workspace/project/srv/julia-bridge/server_lite.jl"
    if ! command -v julia >/dev/null 2>&1; then
        log "julia not on PATH -- multi-iso orchestrator disabled (engine degrades to empty)"
        return 0
    fi
    if [[ ! -f "$script" ]]; then
        log "server_lite.jl not found at $script -- multi-iso orchestrator disabled"
        return 0
    fi
    log "Starting julia multi-iso orchestrator (server_lite.jl on 127.0.0.1:8090)..."
    julia --startup-file=no --compile=min \
        --project=/workspace/project/srv/julia-bridge "$script" --port 8090 \
        >/tmp/julia-bridge.log 2>&1 &
    JULIA_BRIDGE_PID=$!
    sleep 1
    log "julia-bridge pid=$JULIA_BRIDGE_PID"
}

# ── Template nginx.conf ────────────────────────────────────────────────────
# Expand the upstream server list. GODOT_UPSTREAM may be a single
# host:port (single-container) or a comma/space-separated list of shard
# hosts (a mesh behind one nginx). ip_hash in the upstream block gives
# sticky routing so a WebSocket session stays on one shard.
# Also configure SSL certs: Let's Encrypt if available, else self-signed.
_setup_nginx() {
    local upstream="${GODOT_UPSTREAM:-localhost:9000}"

    # Build the server lines for the upstream block (8-space indent to
    # match nginx.conf). Commas and spaces both separate hosts.
    local list="${upstream//,/ }"
    local servers=""
    local host
    for host in $list; do
        servers="${servers}        server ${host};"$'\n'
    done

    if grep -q "GODOT_UPSTREAM_SERVERS" /etc/nginx/nginx.conf 2>/dev/null; then
        python3 - "$servers" <<'PYEOF'
import sys
servers = sys.argv[1].rstrip("\n")
path = "/etc/nginx/nginx.conf"
with open(path) as fh:
    content = fh.read()
content = content.replace("        # GODOT_UPSTREAM_SERVERS", servers)
with open(path, "w") as fh:
    fh.write(content)
PYEOF
        log "nginx upstream: $upstream"
    elif grep -q "GODOT_UPSTREAM" /etc/nginx/nginx.conf 2>/dev/null; then
        # Legacy single-server placeholder (pre-mesh config).
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
    WEBHOOK_BRIDGE_HOST="${WEBHOOK_BRIDGE_HOST:-0.0.0.0}" \
    python3 /workspace/project/srv/webhook-bridge/main.py &
    WEBHOOK_BRIDGE_PID=$!
    # Give the sidecars a moment to bind their ports.
    sleep 1
    log "pg-bridge pid=$PG_BRIDGE_PID  redis-bridge pid=$REDIS_BRIDGE_PID  webhook-bridge pid=$WEBHOOK_BRIDGE_PID  noaa-kp: not started in test mode"

    cleanup_bridges() {
        kill "$PG_BRIDGE_PID" 2>/dev/null || true
        kill "$REDIS_BRIDGE_PID" 2>/dev/null || true
        kill "$WEBHOOK_BRIDGE_PID" 2>/dev/null || true
        wait "$PG_BRIDGE_PID" 2>/dev/null || true
        wait "$REDIS_BRIDGE_PID" 2>/dev/null || true
        wait "$WEBHOOK_BRIDGE_PID" 2>/dev/null || true
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
    log "Running webhook-bridge tests..."
    python3 /workspace/project/srv/webhook-bridge/test_webhook_bridge.py >/tmp/webhook-bridge-test.log 2>&1 || {
        log "FAIL: webhook-bridge tests"; tail -n 30 /tmp/webhook-bridge-test.log; exit 1
    }

    # Godot smoke tests. Run every tests/test_*.gd under the project.
    # cwd is already the Godot project root, so the glob is tests/*.gd
    # and the script path is res://tests/<file>. The previous form
    # (glob game/tests/*.gd from inside game/, script res://<basename>)
    # matched nothing and invoked a path that does not exist, so the
    # loop ran zero tests and still logged success -- a false green.
    # This is the full test_*.gd set and runs serially; for the faster
    # parallel path use scripts/godot_test_runner.sh --all (the one runner).
    cd /workspace/project/game
    for test_file in tests/test_*.gd; do
        [[ -f "$test_file" ]] || continue
        log "  Running: $test_file"
        godot --headless --path /workspace/project/game \
            --script "res://$test_file" || {
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

    # Julia multi-iso orchestrator (mirrors the entity roster into the
    # multi-axis index; fails soft when julia is absent)
    _start_julia_bridge

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
    _start_state_bridges
    _start_julia_bridge

    # NOAA Kp sidecar: feeds the CosmicService flywheel with real
    # planetary K-index (solar wind -> weather). Fails soft: the game
    # keeps its last reading and weather demotes to trad via the
    # frame's staleness law.
    log "Starting noaa-kp sidecar..."
    NOAA_SIDECAR_HOST="127.0.0.1" NOAA_SIDECAR_PORT="8082" \
    python3 /workspace/project/srv/noaa_kp_sidecar.py &
    NOAA_KPID=$!

    # webhook-bridge: the payment processor's public HTTP entry. nginx
    # routes /hooks/ here; the engine transport polls the same queue
    # and feeds the provider's handle_webhook once per delivery.
    log "Starting webhook-bridge..."
    WEBHOOK_BRIDGE_HOST="127.0.0.1" WEBHOOK_BRIDGE_PORT="8083" \
    python3 /workspace/project/srv/webhook-bridge/main.py &
    WEBHOOK_BRIDGE_PID=$!

    # Give the sidecars a moment to bind their ports.
    sleep 1
    log "pg-bridge pid=$PG_BRIDGE_PID  redis-bridge pid=$REDIS_BRIDGE_PID  noaa-kp pid=$NOAA_KPID  webhook-bridge pid=$WEBHOOK_BRIDGE_PID"

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

# ── COORDINATOR MODE ───────────────────────────────────────────────────────
# Shard mesh Phase 3: the coordinator owns the shard registry and the
# cross-shard bus, but serves NO game port -- it is not a shard. It still
# needs the shared-state bridges (postgres for the registry, redis for the
# bus) and boots Godot headless so the engine binds the mesh.
if [[ "$START_MODE" == "coordinator" ]]; then
    log "Mode: COORDINATOR — Godot headless (registry + bus; no game port)"
    _start_state_bridges
    _start_julia_bridge
    godot --headless --path /workspace/project/game &
    log "Coordinator running (no game port; role=${START_MODE})"
    log "PID: $!"
    tail -f /dev/null
    exit 0
fi

# ── EDGE MODE ─────────────────────────────────────────────────────────────
# Shard mesh Phase 3.1: the edge is a PURE L7 proxy -- nginx only, no Godot
# and no game port of its own. It fronts the shard replicas with ip_hash
# sticky routing so a WebSocket session (and the client's follow-up HTTP)
# stays on one shard. GODOT_UPSTREAM is the comma/space shard host list
# (e.g. "shard-1:9000,shard-2:9000"); each entry becomes one upstream
# server line. The engine's EDGE_TRANSPORT=websocket shards speak the
# protocol this proxy upgrades.
if [[ "$START_MODE" == "edge" ]]; then
    log "Mode: EDGE — nginx L7 proxy (sticky routing to shards; no game port)"
    _setup_nginx
    nginx -g 'daemon off;' &
    log "Edge running (upstream=${GODOT_UPSTREAM:-localhost:9000})"
    log "PID: $!"
    tail -f /dev/null
    exit 0
fi

# ── HEADLESS MODE ─────────────────────────────────────────────────────────
# Godot headless only — no nginx, no VNC. Good for CI runners, bots.
if [[ "$START_MODE" == "headless" ]]; then
    log "Mode: HEADLESS — Godot headless only"

    # A headless container is the shard role: it needs the shared-state
    # bridges up before Godot boots so the engine can reach postgres/redis
    # (or the sqlite/inmemory fallbacks when unset).
    _start_state_bridges
    _start_julia_bridge

    godot --headless --path /workspace/project/game &

    log "Godot headless running on port ${GODOT_PORT:-9000} (shard ${SHARD_ID:-shard_1})"
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
log "Valid modes: dev, prod, headless, coordinator, edge, test"
exit 1
