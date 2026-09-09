-- V20260909_001__init_kv.sql
--
-- Creates the generic key-value table used by DictStore.
-- All services that migrated from user:// + FileAccess + JSON
-- now persist through this table via AdapterRegistry.
--
-- Idempotent: safe to re-run.

CREATE TABLE IF NOT EXISTS kv (
    key       VARCHAR(255) PRIMARY KEY,
    value     TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_kv_updated ON kv(updated_at);
