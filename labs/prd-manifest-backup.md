# PRD: Manifest Backup (D031)

> **For:** sub-agent implementation
> **Phase:** 1 (per `world-building-arch.md` §14)
> **Depends on:** Postgres (already in docker-compose), S3 (or equivalent)
> **Unblocks:** disaster recovery, the recursive seed-state model's durability

## 1. Introduction/Overview

The `WorldManifest` (the durable storage for all `locked`
seeds and world-level config) is replicated to 3 storage
tiers: Postgres (primary + 1 read replica), S3 (daily
snapshot), and a cold tier (30-day retention). Recovery:
`manifest --restore --from <date>` rebuilds state to that
snapshot. **All player state < date is lost.** This is the
documented price of the recursive model.

**Why this exists:** Per arch doc §6.4 and the validation's
Tier-1 issue #3, the manifest SPOF was a real risk. The
recursive seed-state model means *every* locked seed
derives from `world_seed` in the manifest. Lose the
manifest = lose the world map, every shard's terrain,
every player's house. Multi-tier is the minimum
acceptable insurance.

**Spec ref:**
[`world-building-arch.md`](./world-building-arch.md) §6.4
(manifest storage), `world-building-risks.md` (D031 pending)

## 2. Goals

- 3 storage tiers: Postgres (primary), S3 (daily snapshot),
  cold tier (30-day retention)
- Daily cron at 03:00 UTC
- Recovery script: `srv/backup/manifest.sh --restore --from <date>`
- Backup integrity: SHA-256 checksum per backup
- 30-day cold retention, then purged
- Documented limitation: "all player state < date is lost"
- Tests cover: backup creation, checksum verification,
  restore, integrity check, cold tier purge

## 3. User Stories

### US-001: backup.sh creates a daily snapshot

**Description:** As a developer, I need a
`srv/backup/backup.sh` that exports the `WorldManifest`
to a compressed JSON file, so it can be uploaded to S3.

**Acceptance Criteria:**
- [ ] Script at `srv/backup/backup.sh`, executable
- [ ] Reads `world_manifest` table from Postgres
- [ ] Exports to `manifest_<UTC_DATE>.json.gz` in
  `srv/backup/staging/`
- [ ] Computes SHA-256 checksum, stores in
  `manifest_<UTC_DATE>.sha256`
- [ ] Returns 0 on success, non-zero on failure
- [ ] Tests: backup file exists, checksum matches,
  compression ratio is reasonable (< 10:1)

### US-002: upload.sh pushes to S3

**Description:** As a developer, I need a
`srv/backup/upload.sh` that uploads the snapshot to
S3, so it's durable off-site.

**Acceptance Criteria:**
- [ ] Script at `srv/backup/upload.sh`, executable
- [ ] Uploads `manifest_<DATE>.json.gz` and the
  `.sha256` file to `s3://synmergia-backups/manifest/<DATE>/`
- [ ] Uses AWS CLI (or equivalent)
- [ ] Returns 0 on success, non-zero on failure
- [ ] Tests: S3 object exists with the right key, content
  matches the local file

### US-003: cold_tier.sh moves old backups to cold

**Description:** As a developer, I need a
`srv/backup/cold_tier.sh` that moves backups older than
7 days to a cold tier (S3 Glacier or equivalent), so the
hot tier doesn't grow unbounded.

**Acceptance Criteria:**
- [ ] Script at `srv/backup/cold_tier.sh`, executable
- [ ] Lists objects in `s3://synmergia-backups/manifest/`
  older than 7 days
- [ ] Moves them to `s3://synmergia-backups-cold/manifest/`
  with Glacier storage class
- [ ] Returns 0 on success
- [ ] Tests: backups older than 7 days are in cold tier,
  recent ones are still in hot tier

### US-004: purge.sh removes backups older than 30 days

**Description:** As a developer, I need a
`srv/backup/purge.sh` that purges cold-tier backups older
than 30 days, so the cold tier doesn't grow unbounded.

**Acceptance Criteria:**
- [ ] Script at `srv/backup/purge.sh`, executable
- [ ] Lists objects in cold tier older than 30 days
- [ ] Deletes them
- [ ] Logs the deletion
- [ ] Returns 0 on success
- [ ] Tests: cold tier has no backups older than 30 days
  after purge

### US-005: restore.sh rebuilds state from a snapshot

**Description:** As an admin, I need a
`srv/backup/restore.sh --from <date>` that rebuilds the
manifest from a snapshot, so I can recover from a
disaster.

**Acceptance Criteria:**
- [ ] Script at `srv/backup/restore.sh`, executable
- [ ] `--from <date>` is required (UTC date, e.g.,
  `2026-09-05`)
- [ ] Downloads the snapshot from S3 (hot or cold tier,
  whichever has it)
- [ ] Verifies the SHA-256 checksum
- [ ] Replaces the `world_manifest` table with the
  snapshot data
- [ ] Logs the restore action (audit trail)
- [ ] Returns 0 on success, non-zero on checksum
  mismatch or download failure
- [ ] Tests: restore from a known snapshot → manifest
  table matches the snapshot; restore with bad
  checksum → non-zero exit

### US-006: Daily cron schedule

**Description:** As an admin, I need the backup chain
to run daily at 03:00 UTC, so backups happen
automatically.

**Acceptance Criteria:**
- [ ] Crontab entry (or equivalent) at 03:00 UTC:
  ```
  0 3 * * * /srv/backup/backup.sh && /srv/backup/upload.sh
  ```
- [ ] Cold tier runs weekly (Sunday 04:00 UTC):
  ```
  0 4 * * 0 /srv/backup/cold_tier.sh
  ```
- [ ] Purge runs daily at 05:00 UTC:
  ```
  0 5 * * * /srv/backup/purge.sh
  ```
- [ ] Tests: cron entries are present, scripts are
  executable

### US-007: Documented limitation

**Description:** As a developer, I need the "all player
state < date is lost" limitation documented, so the
team understands the price of the recursive model.

**Acceptance Criteria:**
- [ ] README at `srv/backup/README.md` includes a
  "Limitations" section
- [ ] The section states: "Restoring from a snapshot
  dated <date> loses all player state created before
  that date. This is the price of the recursive seed-
  state model. Per-player backups (preserved across
  manifest loss) are a v2 feature."
- [ ] Tests: README contains the limitation text

## 4. Functional Requirements

- **FR-1:** 4 shell scripts: `backup.sh`, `upload.sh`,
  `cold_tier.sh`, `purge.sh`, `restore.sh`
- **FR-2:** Daily cron at 03:00 UTC for backup + upload
- **FR-3:** Weekly cron for cold tier (Sunday 04:00 UTC)
- **FR-4:** Daily cron for purge (05:00 UTC)
- **FR-5:** SHA-256 checksum on every backup
- **FR-6:** Restore script with `--from <date>` arg
- **FR-7:** Audit log for restores
- **FR-8:** Documented limitation in README

## 5. Non-Goals (Out of Scope)

- NO per-player backups (out of scope; the recursive
  model means per-player state is lost on manifest loss
  unless we add per-player backups, which is a v2
  feature)
- NO incremental backups (full snapshot per day; the
  manifest is small enough that this is fine)
- NO backup encryption at rest (rely on S3's server-
  side encryption; client-side encryption is a v2
  concern)
- NO cross-region replication (single region for v1;
  cross-region is a v2 concern)
- NO backup verification cron (we verify on restore
  only; daily verification is a v2 concern)

## 6. Design Considerations

- **Why 3 tiers:** Postgres (always-on, fast recovery),
  S3 (off-site, durable), cold (cheap long-term). The
  tiers balance recovery speed vs cost.
- **Why daily:** matches the typical RPO (recovery point
  objective) for an MMORPG. Hourly is overkill; weekly
  is too coarse.
- **Why 30-day cold retention:** long enough to recover
  from a slow-burning disaster (e.g., a bug that
  corrupts data over weeks); short enough to bound cost.
- **Why documented limitation:** the recursive model has
  a real cost. Documenting it makes the cost visible
  and motivates per-player backups as a v2 feature.

## 7. Technical Considerations

- **Bash, POSIX-compliant.** Runs in the synmergia
  container (or equivalent).
- **Postgres client:** `psql` for the dump.
- **S3 client:** `aws` CLI.
- **Cron:** standard `cron` daemon.
- **Tests:** `srv/backup/test_backup.sh` — runs each
  script against a test Postgres + localstack S3
  fixture, verifies the round-trip.

## 8. Success Metrics

- All 7 user stories have passing tests
- Daily backup creates a valid snapshot
- S3 upload succeeds
- Cold tier move works
- Purge removes old backups
- Restore rebuilds the manifest
- Checksum verification catches corruption
- One commit, pushed to main
- `labs/world-building-arch.md` §13 component map status
  updated: D031 from `TODO` to `DONE`

## 9. Open Questions

1. **Compression:** gzip is the default. Should we use
   zstd for better compression? My read: gzip is fine
   for v1; the manifest is small.
2. **Backup verification:** should we run a daily verify
   (download + checksum + parse) to catch silent
   corruption? My read: yes, but v2. v1 verifies on
   restore only.
3. **Cross-region:** should the hot tier be replicated
   to a second region? My read: yes, but v2. v1 is
   single region.

## 10. Definition of Done

- [ ] All 5 scripts implemented and pushed to main
- [ ] README documents the limitation
- [ ] Cron entries documented (in README, applied by
  the deployment)
- [ ] Tests passing
- [ ] `labs/world-building-arch.md` §13 component map
  updated
- [ ] Single commit, conventional message format
- [ ] Smoke test: backup → upload → cold tier → purge
  → restore round-trip
