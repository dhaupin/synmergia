#!/bin/bash
# Frame Bridge Entrypoint Script
# Handles initialization and graceful shutdown

set -e

echo "Starting Synmergia Frame Bridge v1"
echo "Port: ${PORT:-8080}"
echo "Log Level: ${LOG_LEVEL:-INFO}"

# Wait for dependencies
if [ -n "$POSTGRES_HOST" ]; then
    echo "Waiting for PostgreSQL at $POSTGRES_HOST:${POSTGRES_PORT:-5432}..."
    while ! pg_isready -h "$POSTGRES_HOST" -p "${POSTGRES_PORT:-5432}" -U "${POSTGRES_USER:-synmergia}" -d "${POSTGRES_DB:-synmergia}" > /dev/null 2>&1; do
        sleep 1
    done
    echo "PostgreSQL is ready"
fi

if [ -n "$REDIS_HOST" ]; then
    echo "Waiting for Redis at $REDIS_HOST:${REDIS_PORT:-6379}..."
    while ! redis-cli -h "$REDIS_HOST" -p "${REDIS_PORT:-6379}" ping > /dev/null 2>&1; do
        sleep 1
    done
    echo "Redis is ready"
fi

# Start the frame server
exec python frame_server.py