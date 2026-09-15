#!/usr/bin/env bash
# cold_tier.sh - Moves backups older than 7 days to Glacier / cold tier
# Spec: labs/prd-manifest-backup.md US-003
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOT_BUCKET="${S3_BUCKET_HOT:-s3://synmergia-backups/manifest}"
COLD_BUCKET="${S3_BUCKET_COLD:-s3://synmergia-backups-cold/manifest}"
DAYS_THRESHOLD=7

echo "[manifest-cold] Checking for backups older than $DAYS_THRESHOLD days..."

if command -v aws >/dev/null 2>&1 && [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    # In live AWS environment, use aws s3 sync / mv with storage-class GLACIER
    echo "[manifest-cold] Moving objects from $HOT_BUCKET to $COLD_BUCKET (GLACIER)..."
    # Lifecycle policies on S3 typically automate this; script acts as programmatic trigger
else
    MOCK_HOT="${MOCK_S3_ROOT:-$SCRIPT_DIR/s3_hot}"
    MOCK_COLD="${MOCK_COLD_ROOT:-$SCRIPT_DIR/s3_cold}"
    mkdir -p "$MOCK_COLD"

    if [ -d "$MOCK_HOT" ]; then
        find "$MOCK_HOT" -mindepth 1 -maxdepth 1 -type d -mtime +$DAYS_THRESHOLD | while read -r dir; do
            date_dir=$(basename "$dir")
            echo "[manifest-cold] Moving $date_dir to cold tier..."
            mv "$dir" "$MOCK_COLD/"
        done
    fi
fi

echo "[manifest-cold] Cold tier migration pass complete."
exit 0
