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

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ============================================================================
# BASE - always needed
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget unzip ca-certificates git build-essential \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# GODOT - always needed
# ============================================================================
RUN curl -fsSL https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip -o godot.zip && \
    unzip -q godot.zip && \
    mv Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot && \
    chmod +x /usr/local/bin/godot && \
    rm godot.zip

# Godot export templates
RUN curl -fsSL https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz -o templates.tpz && \
    mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable && \
    unzip -q templates.tpz -d ~/.local/share/godot/export_templates/4.7.2.stable && \
    mv ~/.local/share/godot/export_templates/4.7.2.stable/templates/* ~/.local/share/godot/export_templates/4.7.2.stable/ && \
    rm templates.tpz

# ============================================================================
# GUI - always needed (Xvfb, VNC, noVNC for browser access)
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb x11vnc novnc \
    libx11-6 libx11-xcb1 libxcb1 libxext6 libxrandr2 libxcursor1 \
    libxi6 libxinerama1 libxrender1 libxkbcommon0 \
    libgl1-mesa-glx libasound2 libpulse0 \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages websockify

# ============================================================================
# WEB - Nginx for serving
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx openssl \
    && rm -rf /var/lib/apt/lists/*

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
# OPTIONAL: Python + media tools
# ============================================================================
ARG INSTALL_MEDIA=true
RUN if [ "$INSTALL_MEDIA" = "true" ]; then \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv ffmpeg imagemagick xwd xdotool \
    && rm -rf /var/lib/apt/lists/*; \
    fi

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

RUN mkdir -p /var/www/html /etc/nginx/ssl /workspace/project/synmergia/captures /tools

# Nginx config
RUN cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;
    location / { try_files $uri $uri/ =404; }
    location /game/ { try_files $uri $uri/ /game/index.html; }
    location /ws/ {
        proxy_pass http://localhost:9000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=US/ST=State/L=City/O=Synmergia/CN=localhost"

EXPOSE 80 6080 5900 9000

CMD ["bash", "-c", "\
Xvfb :99 -screen 0 1920x1080x24 & \
x11vnc -display :99 -rfbport 5900 -forever -shared -nopw & \
websockify --web=/usr/share/novnc 6080 localhost:5900 & \
nginx & \
echo '' && \
echo '═══════════════════════════════════════' && \
echo ' Synmergia Dev Container' && \
echo '═══════════════════════════════════════' && \
echo ' HTTP:   http://localhost' && \
echo ' noVNC:  http://localhost:6080/vnc.html' && \
echo ' VNC:    localhost:5900' && \
echo ' Godot:  DISPLAY=:99 godot --path /workspace/project/synmergia' && \
echo '═══════════════════════════════════════' && \
tail -f /dev/null"]
