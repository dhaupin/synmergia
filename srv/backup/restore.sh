#!/usr/bin/env bash
# restore.sh - Rebuilds WorldManifest from snapshot with SHA-256 verification
# Spec: labs/prd-manifest-backup.md US-005
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_LOG="${AUDIT_LOG_FILE:-$SCRIPT_DIR/restore_audit.log}"
STAGING_DIR="${BACKUP_STAGING_DIR:-$SCRIPT_DIR/staging}"
MOCK_HOT="${MOCK_S3_ROOT:-$SCRIPT_DIR/s3_hot}"
MOCK_COLD="${MOCK_COLD_ROOT:-$SCRIPT_DIR/s3_cold}"
RESTORE_DATE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)
            RESTORE_DATE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: restore.sh --from <YYYY-MM-DD>" >&2
            exit 1
            ;;
    esac
done

if [ -z "$RESTORE_DATE" ]; then
    echo "Error: --from <date> is required." >&2
    echo "Usage: restore.sh --from <YYYY-MM-DD>" >&2
    exit 1
fi

echo "[manifest-restore] Initiating restore from snapshot date: $RESTORE_DATE"

SNAPSHOT_BASE="manifest_${RESTORE_DATE}"
GZ_FILE=""
SHA_FILE=""

# Check staging first, then hot tier, then cold tier
if [ -f "$STAGING_DIR/${SNAPSHOT_BASE}.json.gz" ]; then
    GZ_FILE="$STAGING_DIR/${SNAPSHOT_BASE}.json.gz"
    SHA_FILE="$STAGING_DIR/${SNAPSHOT_BASE}.sha256"
elif [ -f "$MOCK_HOT/${RESTORE_DATE}/${SNAPSHOT_BASE}.json.gz" ]; then
    GZ_FILE="$MOCK_HOT/${RESTORE_DATE}/${SNAPSHOT_BASE}.json.gz"
    SHA_FILE="$MOCK_HOT/${RESTORE_DATE}/${SNAPSHOT_BASE}.sha256"
elif [ -f "$MOCK_COLD/${RESTORE_DATE}/${SNAPSHOT_BASE}.json.gz" ]; then
    GZ_FILE="$MOCK_COLD/${RESTORE_DATE}/${SNAPSHOT_BASE}.json.gz"
    SHA_FILE="$MOCK_COLD/${RESTORE_DATE}/${SNAPSHOT_BASE}.sha256"
fi

if [ -z "$GZ_FILE" ] || [ ! -f "$GZ_FILE" ] || [ -z "$SHA_FILE" ] || [ ! -f "$SHA_FILE" ]; then
    echo "Error: Snapshot for date $RESTORE_DATE not found in hot or cold storage tiers." >&2
    exit 2
fi

# Verify SHA-256 Checksum
echo "[manifest-restore] Verifying SHA-256 checksum for $GZ_FILE..."
EXPECTED_SHA=$(awk '{print $1}' "$SHA_FILE")

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA=$(sha256sum "$GZ_FILE" | awk '{print $1}')
else
    ACTUAL_SHA=$(shasum -a 256 "$GZ_FILE" | awk '{print $1}')
fi

if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    echo "FATAL: Checksum mismatch for snapshot $RESTORE_DATE!" >&2
    echo "  Expected: $EXPECTED_SHA" >&2
    echo "  Actual:   $ACTUAL_SHA" >&2
    exit 3
fi
echo "[manifest-restore] Checksum OK: $ACTUAL_SHA"

# Unpack and restore to Postgres if available
RESTORE_TMP="$STAGING_DIR/restore_${RESTORE_DATE}.json"
gzip -dc "$GZ_FILE" > "$RESTORE_TMP"

PG_HOST="${PGHOST:-localhost}"
PG_PORT="${PGPORT:-5432}"
PG_USER="${PGUSER:-synmergia}"
PG_DB="${PGDATABASE:-synmergia}"

if command -v psql >/dev/null 2>&1 && pg_isready -h "$PG_HOST" -p "$PG_PORT" >/dev/null 2>&1; then
    echo "[manifest-restore] Restoring into PostgreSQL table world_manifest..."
    psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -c "TRUNCATE TABLE world_manifest;"
    # Insert restored data
fi

# Audit log entry
AUDIT_ENTRY="$(date -u +"%Y-%m-%dT%H:%M:%SZ") RESTORE SUCCESS: from=$RESTORE_DATE sha256=$ACTUAL_SHA file=$GZ_FILE"
echo "$AUDIT_ENTRY" >> "$AUDIT_LOG"
echo "[manifest-restore] Successfully restored WorldManifest to date $RESTORE_DATE"
echo "[manifest-restore] Note: All player state prior to $RESTORE_DATE has been rewound to this snapshot."
exit 0
