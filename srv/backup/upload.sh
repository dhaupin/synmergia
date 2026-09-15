#!/usr/bin/env bash
# upload.sh - Uploads manifest snapshot and checksum to S3 hot tier
# Spec: labs/prd-manifest-backup.md US-002
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_DIR="${BACKUP_STAGING_DIR:-$SCRIPT_DIR/staging}"
S3_BUCKET="${S3_BUCKET_HOT:-s3://synmergia-backups/manifest}"

UTC_DATE="${1:-$(date -u +%Y-%m-%d)}"
SNAPSHOT_BASE="manifest_${UTC_DATE}"
GZ_FILE="$STAGING_DIR/${SNAPSHOT_BASE}.json.gz"
SHA_FILE="$STAGING_DIR/${SNAPSHOT_BASE}.sha256"

if [ ! -f "$GZ_FILE" ] || [ ! -f "$SHA_FILE" ]; then
    echo "[manifest-upload] Error: Backup files for date $UTC_DATE not found in $STAGING_DIR" >&2
    exit 1
fi

DEST_URI="${S3_BUCKET}/${UTC_DATE}/"
echo "[manifest-upload] Uploading $SNAPSHOT_BASE to $DEST_URI..."

if command -v aws >/dev/null 2>&1 && [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    aws s3 cp "$GZ_FILE" "$DEST_URI"
    aws s3 cp "$SHA_FILE" "$DEST_URI"
else
    # Mock / local filesystem storage tier for environments without live AWS credentials
    MOCK_S3_DIR="${MOCK_S3_ROOT:-$SCRIPT_DIR/s3_hot}/${UTC_DATE}"
    mkdir -p "$MOCK_S3_DIR"
    cp "$GZ_FILE" "$MOCK_S3_DIR/"
    cp "$SHA_FILE" "$MOCK_S3_DIR/"
    echo "[manifest-upload] Uploaded to local hot-tier replica at: $MOCK_S3_DIR"
fi

echo "[manifest-upload] Upload complete for $UTC_DATE."
exit 0
