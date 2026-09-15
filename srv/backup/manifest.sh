#!/usr/bin/env bash
# manifest.sh - Unified CLI interface for WorldManifest disaster recovery
# Spec: labs/prd-manifest-backup.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: manifest.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --backup [date]            Create snapshot and upload to S3"
    echo "  --restore --from <date>    Restore manifest to snapshot"
    echo "  --status                   Show current backup status and staging"
    echo "  --cold-tier                Run weekly cold tier archival pass"
    echo "  --purge                    Run 30-day retention purge"
    exit 1
}

if [ $# -eq 0 ]; then
    usage
fi

case "$1" in
    --backup)
        shift
        "$SCRIPT_DIR/backup.sh" "$@"
        "$SCRIPT_DIR/upload.sh" "$@"
        ;;
    --restore)
        shift
        "$SCRIPT_DIR/restore.sh" "$@"
        ;;
    --cold-tier)
        "$SCRIPT_DIR/cold_tier.sh"
        ;;
    --purge)
        "$SCRIPT_DIR/purge.sh"
        ;;
    --status)
        echo "=== WorldManifest Backup Status ==="
        echo "Staging files:"
        ls -lh "$SCRIPT_DIR/staging" 2>/dev/null || echo "  (none)"
        echo ""
        echo "Audit Log (last 5 entries):"
        tail -n 5 "$SCRIPT_DIR/restore_audit.log" 2>/dev/null || echo "  (no restore events logged)"
        ;;
    *)
        usage
        ;;
esac
