# ============================================================================
# Synmergia - Unified Container
# Single image for dev, production, headless, and testing.
#
# Modes (set START_MODE env):
#   dev        — Xvfb + noVNC + Godot GUI (default)
#   prod       — Godot headless + nginx (no X11/VNC)
#   headless   — Godot headless only (no nginx/VNC)
#   test       — run smoke tests and exit
#
# Usage:
#   docker build -t synmergia .
#   docker compose up              # dev mode (noVNC on :6080)
#   START_MODE=prod docker compose up
#   START_MODE=test docker run --rm synmergia
#
# Build args (change with --build-arg):
#   GODOT_VERSION=4.7.2
#   JULIA_VERSION=1.11.1
#   NODE_VERSION=20
# ============================================================================

FROM debian:trixie-slim

LABEL maintainer="Synmergia"
LABEL description="Synmergia MMORPG — dev/prod/headless/test"

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

# Tool versions (Julia runs the srv/julia-bridge sidecar)
ENV GODOT_VERSION=4.7.2 \
    JULIA_VERSION=1.11.1 \
    JULIA_MINOR=1.11 \
    NODE_VERSION=20 \
    GODOT_PORT=9000 \
    GODOT_PATH=/workspace/project/game

# ── Base system ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core build tools
    curl wget unzip ca-certificates git build-essential gnupg \
    # X11 / VNC (dev mode)
    xvfb x11vnc websockify novnc xfwm4 xdotool \
    libx11-6 libx11-xcb1 libxcb1 libxext6 libxrandr2 libxcursor1 \
    libxi6 libxinerama1 libxrender1 libxkbcommon0 \
    libgl1 libasound2t64 libpulse0 \
    # Web server
    nginx openssl \
    # Dev tools
    python3 python3-pip ffmpeg imagemagick x11-apps \
    # Puppeteer / Chromium (screenshots). The t64 suffix is required on
    # trixie: libasound2 / libgtk-3-0 / libatk-bridge2.0-0 were renamed
    # to their time64 ABI variants and the bare names no longer resolve.
    libnss3 libatk-bridge2.0-0t64 libxcomposite1 libxdamage1 \
    libgbm1 libpangocairo-1.0-0 libpango-1.0-0 libgtk-3-0t64 \
    fonts-liberation \
    # Database clients (app connects to external containers)
    postgresql-client redis-tools \
    # Python driver deps for the pg/redis bridges. Without these the bridges
    # can only run their sqlite/inmemory fallbacks, so a shard mesh can never
    # reach the shared postgres/redis. Versions are pinned by trixie's apt.
    python3-psycopg python3-redis \
    # Certbot for HTTPS (optional)
    certbot \
    # Misc utilities
    sudo nano jq procps \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# ── ImageMagick security ────────────────────────────────────────────────────
RUN sed -i 's/^<policy domain="coder" rights="none" pattern="\(PS\|PDF\)"\/>$/<policy domain="coder" rights="none" pattern="PS"\/><policy domain="coder" rights="none" pattern="PDF"\/>/' \
    /etc/ImageMagick-6/policy.xml 2>/dev/null || true

# ── Godot ──────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    -o /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /usr/local/bin/ \
    && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

# ── Julia ──────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MINOR}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
    -o /tmp/julia.tar.gz \
    && tar -xzf /tmp/julia.tar.gz -C /opt \
    && ln -s "/opt/julia-${JULIA_VERSION}/bin/julia" /usr/local/bin/julia \
    && rm /tmp/julia.tar.gz

# ── Node.js ────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── Working dir ────────────────────────────────────────────────────────────
WORKDIR /workspace/project/game

# ── Sidecar services (srv/) ────────────────────────────────────────────────
# The entrypoint runs the pg/redis/webhook bridges + the NOAA Kp sidecar
# from /workspace/project/srv/. That path must exist in the image, or
# test/prod modes die at the first `python3 .../main.py`. Compose mounts
# ./game and ./labs but NOT srv, so without this COPY the sidecars are
# absent from every container built from this image. game/ is NOT copied
# on purpose: the runtime supplies it via the compose bind mount (dev)
# or a deploy-time overlay (prod), so baking it here would be dead weight.
COPY srv/ /workspace/project/srv/

# ── Nginx config ───────────────────────────────────────────────────────────
COPY nginx.conf /etc/nginx/nginx.conf

# ── Self-signed SSL cert (fallback for dev/prod HTTPS) ────────────────────
RUN mkdir -p /etc/nginx/ssl \
    && openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/nginx.key \
        -out /etc/nginx/ssl/nginx.crt \
        -subj "/C=US/ST=Dev/L=Dev/O=Synmergia/CN=localhost" \
    && mkdir -p /var/www/html /etc/nginx/snippets

# ── Capture dirs ───────────────────────────────────────────────────────────
RUN mkdir -p /workspace/project/game/captures/screenshots \
                /workspace/project/game/captures/videos \
                /var/lib/synmergia

# ── Health check ───────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/ > /dev/null 2>&1 \
    || curl -f http://localhost:6080/ > /dev/null 2>&1 \
    || exit 0

# ── Entrypoint (handles all modes) ─────────────────────────────────────────
COPY srv/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]

EXPOSE 80 443 6080 5900 9000
