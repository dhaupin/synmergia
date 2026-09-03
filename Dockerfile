# ============================================================================
# Synmergia - Development Container
# One image. Build what you need.
#
# Usage:
#   docker build -t synmergia .
#   docker compose up
#
# Optional build args (--build-arg):
#   INSTALL_JULIA=true     # Julia (scientific computing)
#   INSTALL_GO=true        # Go (custom tools)
#   INSTALL_BLENDER=true   # Blender (3D assets) - large!
# ============================================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

# Versions
ENV GODOT_VERSION=4.7.2
ENV JULIA_VERSION=1.11.1
ENV JULIA_MINOR=1.11
ENV GO_VERSION=1.23.1
ENV NODE_VERSION=20

# BASE - always needed
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip ca-certificates git build-essential \
    xvfb x11vnc novnc \
    libx11-6 libx11-xcb1 libxcb1 libxext6 libxrandr2 libxcursor1 \
    libxi6 libxinerama1 libxrender1 libxkbcommon0 \
    libgl1-mesa-glx libasound2 libpulse0 \
    nginx openssl \
    python3 python3-pip ffmpeg imagemagick x11-apps gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Secure ImageMagick
RUN sed -i 's/^<policy domain="coder" rights="none" pattern="\(PS\|PDF\|EPS\|VIDEO\|HTTPD\|DOSMEXEC\)"\/>/<policy domain="coder" rights="none" pattern="PS"\/><policy domain="coder" rights="none" pattern="PDF"\/>/' \
    /etc/ImageMagick-6/policy.xml 2>/dev/null || true

RUN pip3 install --no-cache-dir --break-system-packages websockify

# GODOT
RUN curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    -o godot.zip && \
    unzip -q godot.zip && \
    mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot && \
    chmod +x /usr/local/bin/godot && \
    rm godot.zip

# OPTIONAL: Julia
ARG INSTALL_JULIA=true
RUN if [ "$INSTALL_JULIA" = "true" ]; then \
    curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MINOR}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
    -o julia.tar.gz && \
    tar -xzf julia.tar.gz -C /opt && \
    ln -s "/opt/julia-${JULIA_VERSION}/bin/julia" /usr/local/bin/julia && \
    rm julia.tar.gz; \
    fi

# OPTIONAL: Go
ARG INSTALL_GO=true
RUN if [ "$INSTALL_GO" = "true" ]; then \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o go.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz; \
    fi
ENV PATH="/usr/local/go/bin:${PATH}" GOPATH="/go"

# OPTIONAL: Blender
ARG INSTALL_BLENDER=false
RUN if [ "$INSTALL_BLENDER" = "true" ]; then \
    apt-get update && apt-get install -y --no-install-recommends blender && rm -rf /var/lib/apt/lists/*; \
    fi

# NODE.JS - for Puppeteer screenshot/agent tooling
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# PUPPETEER - Chromium browser for screenshot.js
# Puppeteer's bundled Chromium needs these deps on Debian
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 libatk-bridge2.0-0 libxcomposite1 libxdamage1 libxrandr2 \
    libgbm1 libasound2 libpangocairo-1.0-0 libpango-1.0-0 libgtk-3-0 \
    fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# SETUP
WORKDIR /workspace/project/synmergia

RUN mkdir -p /var/www/html /etc/nginx/ssl /workspace/project/synmergia/captures

# Screenshot/agent tooling — Puppeteer
# Installs puppeteer + minimist into synmergia/scripts/node_modules
# so agents can run screenshot.js inside the container
COPY synmergia/scripts/package.json synmergia/scripts/
RUN cd synmergia/scripts && npm install --no-audit --no-fund

# Nginx config
RUN printf '%s\n' \
    'server {' \
    '    listen 80 default_server;' \
    '    root /var/www/html;' \
    '    index index.html;' \
    '    server_name _;' \
    '    add_header X-Frame-Options "SAMEORIGIN" always;' \
    '    add_header X-Content-Type-Options "nosniff" always;' \
    '    add_header Referrer-Policy "no-referrer" always;' \
    '    autoindex on;' \
    '    location / { try_files $uri $uri/ =404; }' \
    '    location /game/ { try_files $uri $uri/ /game/index.html; }' \
    '    location /ws/ {' \
    '        proxy_pass http://localhost:9000;' \
    '        proxy_http_version 1.1;' \
    '        proxy_set_header Upgrade $http_upgrade;' \
    '        proxy_set_header Connection "upgrade";' \
    '        proxy_read_timeout 86400;' \
    '    }' \
    '}' > /etc/nginx/sites-available/default

# Self-signed cert
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=US/ST=Dev/L=Dev/O=Synmergia/CN=localhost"

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80 6080 5900 9000

ENTRYPOINT ["/bin/bash", "-c", "\
echo 'Starting Synmergia...'; \
Xvfb :99 -screen 0 1920x1080x24 & \
sleep 1; \
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw -bg 2>/dev/null || true; \
websockify --web=/usr/share/novnc 6080 localhost:5900 &>/dev/null & \
sleep 1; \
nginx -g 'daemon off;' & \
echo ''; \
echo '================================================'; \
echo ' Synmergia Dev Container'; \
echo '================================================'; \
echo ' HTTP:   http://localhost'; \
echo ' noVNC:  http://localhost:6080/vnc.html'; \
echo ' VNC:    localhost:5900'; \
echo ' Godot:  DISPLAY=:99 godot --path /workspace/project/synmergia'; \
echo '================================================'; \
tail -f /dev/null"]

CMD ["tail", "-f", "/dev/null"]
