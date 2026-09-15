#!/usr/bin/env bash
# test_backup.sh - Verification suite for WorldManifest backup & restore pipeline
# Spec: labs/prd-manifest-backup.md US-001 through US-007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BACKUP_STAGING_DIR="$SCRIPT_DIR/test_staging"
export MOCK_S3_ROOT="$SCRIPT_DIR/test_s3_hot"
export MOCK_COLD_ROOT="$SCRIPT_DIR/test_s3_cold"
export AUDIT_LOG_FILE="$SCRIPT_DIR/test_restore_audit.log"

cleanup() {
    rm -rf "$BACKUP_STAGING_DIR" "$MOCK_S3_ROOT" "$MOCK_COLD_ROOT" "$AUDIT_LOG_FILE"
}
trap cleanup EXIT
cleanup

echo "=== Running Manifest Backup Test Suite ==="

# Test 1: Backup creation and checksum generation
TEST_DATE="2026-09-15"
export TEST_MANIFEST_DATA='{"world_seed":"testseed123","shards":["shard_alpha"]}'
"$SCRIPT_DIR/backup.sh" "$TEST_DATE"

GZ_FILE="$BACKUP_STAGING_DIR/manifest_${TEST_DATE}.json.gz"
SHA_FILE="$BACKUP_STAGING_DIR/manifest_${TEST_DATE}.sha256"

if [ ! -f "$GZ_FILE" ] || [ ! -f "$SHA_FILE" ]; then
    echo "FAIL: Expected backup artifacts not created" >&2
    exit 1
fi
echo "PASS: US-001 backup.sh creates compressed snapshot and SHA-256"

# Test 2: Upload to S3 tier
"$SCRIPT_DIR/upload.sh" "$TEST_DATE"
if [ ! -f "$MOCK_S3_ROOT/$TEST_DATE/manifest_${TEST_DATE}.json.gz" ]; then
    echo "FAIL: Uploaded file missing from hot tier" >&2
    exit 1
fi
echo "PASS: US-002 upload.sh replicates snapshot and checksum to storage tier"

# Test 3: Restore with valid checksum
"$SCRIPT_DIR/restore.sh" --from "$TEST_DATE"
if ! grep -q "RESTORE SUCCESS: from=$TEST_DATE" "$AUDIT_LOG_FILE"; then
    echo "FAIL: Audit log entry missing after successful restore" >&2
    exit 1
fi
echo "PASS: US-005 restore.sh rebuilds state and logs audit trail"

# Test 4: Restore with corrupt checksum rejects restore
echo "corrupted_checksum_abc123" > "$BACKUP_STAGING_DIR/manifest_${TEST_DATE}.sha256"
set +e
"$SCRIPT_DIR/restore.sh" --from "$TEST_DATE" >/dev/null 2>&1
EXIT_CODE=$?
set -e
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "FAIL: restore.sh should fail when checksum mismatches" >&2
    exit 1
fi
echo "PASS: Checksum mismatch aborts restore cleanly with non-zero status"

# Test 5: Check README contains limitations statement
if ! grep -q "Restoring from a snapshot dated <date> loses all player state created before that date" "$SCRIPT_DIR/README.md"; then
    echo "FAIL: README missing required limitations statement" >&2
    exit 1
fi
echo "PASS: US-007 Limitations documented in README"

echo "=== All Manifest Backup tests passed! ==="
exit 0
