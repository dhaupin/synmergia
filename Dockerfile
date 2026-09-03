# ============================================================================
# Synmergia - Development Container
# One image. Build what you need.
#
# Usage:
#   docker build -t synmergia .
#   docker compose up
#
# Optional build args (--build-arg):
#   INSTALL_JULIA=true     # Julia 1.11 (scientific computing)
#   INSTALL_GO=true        # Go 1.23 (custom tools)
#   INSTALL_MEDIA=true     # FFmpeg + ImageMagick (video/screenshots)
#   INSTALL_BLENDER=true   # Blender (3D assets) - large!
# ============================================================================

FROM debian:bookworm-slim AS base

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

# ============================================================================
# BASE - always needed (single layer for caching)
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip ca-certificates git build-essential \
    xvfb x11vnc novnc \
    libx11-6 libx11-xcb1 libxcb1 libxext6 libxrandr2 libxcursor1 \
    libxi6 libxinerama1 libxrender1 libxkbcommon0 \
    libgl1-mesa-glx libasound2 libpulse0 \
    nginx openssl \
    python3 python3-pip ffmpeg imagemagick x11-apps \
    && rm -rf /var/lib/apt/lists/* \
    # Restrict ImageMagick for security
    && sed -i 's/^<policy domain="coder" rights="none" pattern="(PS|PDF|EPS|VIDEO|HTTPD|DOSMEXEC)"\/>//' /etc/ImageMagick-6/policy.xml || true \
    || cat > /etc/ImageMagick-6/policy.xml << 'POLICY'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policymap [
  <policy domain="coder" rights="none" pattern="PS"/>
  <policy domain="coder" rights="none" pattern="PDF"/>
  <policy domain="coder" rights="none" pattern="EPS"/>
  <policy domain="coder" rights="none" pattern="XPS"/>
  <policy domain="coder" rights="none" pattern="VIDEO"/>
  <policy domain="coder" rights="none" pattern="MSL"/>
  <policy domain="coder" rights="none" pattern="MVG"/>
  <policy domain="coder" rights="none" pattern="HTTPS"/>
  <policy domain="coder" rights="none" pattern="HTTP"/>
  <policy domain="path" rights="none" pattern="@*"/>
]
>
POLICY

RUN pip3 install --no-cache-dir --break-system-packages websockify

# ============================================================================
# GODOT - always needed
# ============================================================================
RUN curl -fsSL https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip -o godot.zip && \
    unzip -q godot.zip && \
    mv Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot && \
    chmod +x /usr/local/bin/godot && \
    rm godot.zip

# Godot export templates (optional - only if building exports)
# RUN curl -fsSL https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz -o templates.tpz && \
#     mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable && \
#     unzip -q templates.tpz -d ~/.local/share/godot/export_templates/4.7.2.stable && \
#     rm templates.tpz

# ============================================================================
# OPTIONAL: Julia
# ============================================================================
ARG INSTALL_JULIA=true
RUN if [ "$INSTALL_JULIA" = "true" ]; then \
    curl -fsSL https://julialang-s3.julialang.org/bin/linux/x64/1.11/julia-1.11.1-linux-x86_64.tar.gz -o julia.tar.gz && \
    tar -xzf julia.tar.gz -C /opt && \
    ln -s /opt/julia-1.11.1/bin/julia /usr/local/bin/julia && \
    rm julia.tar.gz; \
    fi

# ============================================================================
# OPTIONAL: Go
# ============================================================================
ARG INSTALL_GO=true
RUN if [ "$INSTALL_GO" = "true" ]; then \
    curl -fsSL https://go.dev/dl/go1.23.1.linux-amd64.tar.gz -o go.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz; \
    fi
ENV PATH="/usr/local/go/bin:${PATH}" GOPATH="/go"

# ============================================================================
# OPTIONAL: Blender (heavy!)
# ============================================================================
ARG INSTALL_BLENDER=false
RUN if [ "$INSTALL_BLENDER" = "true" ]; then \
    apt-get update && apt-get install -y --no-install-recommends \
    blender && rm -rf /var/lib/apt/lists/*; \
    fi

# ============================================================================
# SETUP
# ============================================================================
WORKDIR /workspace/project/synmergia

RUN mkdir -p /var/www/html /etc/nginx/ssl /workspace/project/synmergia/captures

# Nginx config
RUN cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    # Allow listing for dev
    autoindex on;

    location / {
        try_files $uri $uri/ =404;
    }
    location /game/ {
        try_files $uri $uri/ /game/index.html;
    }
    location /ws/ {
        proxy_pass http://localhost:9000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
EOF

# Self-signed cert (dev only)
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=US/ST=Dev/L=Dev/O=Synmergia/CN=localhost"

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80 6080 5900 9000

# Entrypoint script
COPY docker/docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
