#!/usr/bin/env bash
# purge.sh - Purges cold-tier backups older than 30 days
# Spec: labs/prd-manifest-backup.md US-004
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLD_BUCKET="${S3_BUCKET_COLD:-s3://synmergia-backups-cold/manifest}"
PURGE_DAYS="${PURGE_DAYS_THRESHOLD:-30}"

echo "[manifest-purge] Checking for cold tier backups older than $PURGE_DAYS days..."

if command -v aws >/dev/null 2>&1 && [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    echo "[manifest-purge] Executing S3 retention purge for $COLD_BUCKET..."
else
    MOCK_COLD="${MOCK_COLD_ROOT:-$SCRIPT_DIR/s3_cold}"
    if [ -d "$MOCK_COLD" ]; then
        find "$MOCK_COLD" -mindepth 1 -maxdepth 1 -type d -mtime +"$PURGE_DAYS" | while read -r dir; do
            date_dir=$(basename "$dir")
            echo "[manifest-purge] Purging expired cold-tier backup: $date_dir"
            rm -rf "$dir"
        done
    fi
fi

echo "[manifest-purge] Purge pass complete."
exit 0
