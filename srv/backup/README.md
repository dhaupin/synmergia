# WorldManifest Backup & Disaster Recovery (D031)

This service manages disaster recovery for the Synmergia `WorldManifest`, the authoritative storage for all locked seeds and world-level configuration.

## Storage Architecture (3 Tiers)

1. **Postgres (Primary)**: Always-on operational store (`world_manifest` table) replicated to a read replica.
2. **S3 Hot Tier (Daily Snapshot)**: Compressed `.json.gz` with cryptographic SHA-256 checksums, generated daily at 03:00 UTC.
3. **Cold Tier (Glacier, 30-Day Retention)**: Snapshots older than 7 days are transitioned to cold storage. Purged after 30 days.

## Cron Schedule

```cron
# Daily backup and upload to hot tier at 03:00 UTC
0 3 * * * /srv/backup/backup.sh && /srv/backup/upload.sh

# Weekly migration to cold tier (Sunday 04:00 UTC)
0 4 * * 0 /srv/backup/cold_tier.sh

# Daily purge of cold-tier archives >30 days old (05:00 UTC)
0 5 * * * /srv/backup/purge.sh
```

## CLI Usage

```bash
# Run on-demand backup
./srv/backup/manifest.sh --backup

# Restore from snapshot
./srv/backup/manifest.sh --restore --from 2026-09-15

# View status and audit logs
./srv/backup/manifest.sh --status
```

## Limitations

Restoring from a snapshot dated <date> loses all player state created before that date. This is the price of the recursive seed-state model. Per-player backups (preserved across manifest loss) are a v2 feature.
