# WorldManifest Backup & Disaster Recovery (D031)

> Part of the [srv sidecar and operations index](../README.md).

This service manages disaster recovery for the Synmergia `WorldManifest`, the authoritative storage for all locked seeds and world-level configuration.

## Storage model

The scripts implement the snapshot, restore, and hot-tier staging path. They do not provision the database, a read replica, S3, or a Glacier lifecycle; those are deployment-specific.

1. **Postgres (primary)** — `world_manifest` in the operational database. A read replica is not created by the default Compose stack.
2. **Hot tier** — compressed `.json.gz` + SHA-256. `upload.sh` writes to `S3_BUCKET_HOT` when AWS credentials are present; otherwise it uses the local `srv/backup/s3_hot/` replica.
3. **Cold tier / 30-day retention** — local `s3_hot` snapshots older than 7 days move to `srv/backup/s3_cold/`; entries older than 30 days are purged. On AWS, wire bucket lifecycle rules for Glacier/expiration; `cold_tier.sh` and `purge.sh` currently log the S3 path only.

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

> **Production check:** `backup.sh` expects a reachable Postgres. If it cannot connect and `TEST_MANIFEST_DATA` is unset, it writes a placeholder template and still exits 0. That is a test fixture, not a backup; verify the snapshot contents before relying on it.

## Limitations

Restoring from a snapshot dated <date> rewinds the world to that point; player state created or changed after that date is lost unless separately backed up. This is the price of the recursive seed-state model. Per-player backups (preserved across manifest loss) are a v2 feature.
