-- V20260907_001__init_accounts.sql
--
-- First migration. Locks the P0 account/auth + character schemas
-- (see labs/prd-db.md sec.3.1-3.3, "LOCKED" tag 2026-09-07).
--
-- Covers the AccountService -> AccountStore -> Postgres and
-- LoginService -> SessionStore vertical slice:
--   - accounts        (AccountService, LoginService)
--   - sessions        (LoginService durable audit; Redis holds the hot token cache)
--   - characters      (PlayerManager)
--
-- inventories / equipment (InventoryService, P0) deferred to
-- V20260907_002__init_inventory so this migration stays focused on
-- the auth surface and lands without depending on item schemas.
--
-- Idempotent: wraps every table/indexes in CREATE ... IF NOT EXISTS.
-- Safe to re-run.

-- ── Accounts ──────────────────────────────────────────────────────────────
-- Primary identity. password_hash is bcrypt/argon2 output (never plaintext).
CREATE TABLE IF NOT EXISTS accounts (
    id              UUID PRIMARY KEY,
    username        VARCHAR(32) UNIQUE NOT NULL,
    email           VARCHAR(255) UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    salt            VARCHAR(64),          -- per-account salt (redundant with argon2, kept for legacy)
    display_name    VARCHAR(32),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login      TIMESTAMPTZ,
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','banned','suspended')),
    ban_reason      TEXT,
    account_level   INTEGER NOT NULL DEFAULT 0,
    premium         BOOLEAN NOT NULL DEFAULT FALSE,
    settings        JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_accounts_username ON accounts(username);
CREATE INDEX IF NOT EXISTS idx_accounts_email    ON accounts(email);
CREATE INDEX IF NOT EXISTS idx_accounts_status   ON accounts(status);

-- ── Sessions (durable audit) ─────────────────────────────────────────────
-- The HOT session cache lives in Redis (SessionStore). This table is the
-- durable audit trail + recovery path: on pg-bridge start, Redis is rebuilt
-- from recently-unexpired sessions here.
CREATE TABLE IF NOT EXISTS sessions (
    id              UUID PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    token_hash      VARCHAR(255) NOT NULL,   -- never store raw token
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    ip_address      VARCHAR(45),
    user_agent      TEXT,
    is_revoked      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_sessions_account   ON sessions(account_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token     ON sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_expires   ON sessions(expires_at);
-- Cleanup: sessions expired > 7 days ago (token_hash still indexed for lookup).
CREATE INDEX IF NOT EXISTS idx_sessions_revoked_expires ON sessions(is_revoked, expires_at);

-- ── Characters ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS characters (
    id              UUID PRIMARY KEY,
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    display_name    VARCHAR(32) UNIQUE NOT NULL,
    species_id      VARCHAR(32) NOT NULL,
    class_id        VARCHAR(32) NOT NULL,
    level           INTEGER NOT NULL DEFAULT 1,
    experience      BIGINT NOT NULL DEFAULT 0,
    gold            BIGINT NOT NULL DEFAULT 0,
    health          INTEGER,
    mana            INTEGER,
    position_x      REAL,
    position_y      REAL,
    position_z      REAL,
    zone_id         VARCHAR(64),
    faction_id      VARCHAR(64),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_online     TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ,
    data            JSONB NOT NULL DEFAULT '{}'   -- flexible per-char blob (abilities, unlocks, ...)
);

CREATE INDEX IF NOT EXISTS idx_characters_account   ON characters(account_id, deleted_at);
CREATE INDEX IF NOT EXISTS idx_characters_display   ON characters(display_name);
CREATE INDEX IF NOT EXISTS idx_characters_zone      ON characters(zone_id) WHERE deleted_at IS NULL;

-- ── Migration metadata ───────────────────────────────────────────────────
-- Tracks which migrations have been applied so the runner can skip on boot.
-- (The runner inserts the version row after a migration commits; this
--  CREATE IF NOT EXISTS is a bootstrap fallback so the metadata table
--  exists even before the runner runs, e.g. during manual psql inspection.)
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    VARCHAR(128) PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum   VARCHAR(64)   -- sha256 of the migration file body
);
