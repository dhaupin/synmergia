# Frame Bridge Container - Multi-stage build for Synmergia Frame
# Stage 1: Build Godot headless with frame scripts
FROM godot:4.7.2 AS builder

WORKDIR /build

# Copy frame source
COPY labs/multi-iso/ ./labs/multi-iso/

# Create minimal Godot project for frame
RUN mkdir -p /build/frame_project/frame && \
    cp -r /build/labs/multi-iso/* /build/frame_project/frame/

# Write project.godot
RUN cat > /build/frame_project/project.godot << 'EOF'
[application]
config/name="SynmergiaFrame"
run/main_scene=""

[autoload]

[input]
EOF

# Stage 2: Runtime with Python bridge
FROM python:3.11-slim

WORKDIR /frame

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    godot4 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy frame server
COPY frame_server.py .

# Copy frame scripts for Python fallback
COPY --from=builder /build/frame_project/frame ./frame

# Create non-root user
RUN useradd -m -u 1000 frameuser && \
    chown -R frameuser:frameuser /frame
USER frameuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Entrypoint
ENTRYPOINT ["python", "frame_server.py"]