-- V20260918_002__init_inventory.sql
--
-- Inventory & Equipment tables (P0).
-- Covers InventoryService -> InventoryStore.
-- Depends on V20260907_001__init_accounts.sql (characters table).
--
-- Idempotent: wraps every table/index in CREATE ... IF NOT EXISTS.
-- Safe to re-run.

-- ── Inventories ─────────────────────────────────────────────────────────────
-- Main bag storage. One row per stack/slot.
CREATE TABLE IF NOT EXISTS inventories (
    id              UUID PRIMARY KEY,
    character_id    UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    slot_index      INTEGER NOT NULL,
    item_id         VARCHAR(64) NOT NULL,
    quantity        INTEGER NOT NULL DEFAULT 1,
    bound           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (character_id, slot_index)
);

-- Composite index for "recent inventory changes by character" (audit, sync)
CREATE INDEX IF NOT EXISTS idx_inventories_char_created ON inventories(character_id, created_at DESC);

-- Index for "find item by character + item_id" (stacking, search)
CREATE INDEX IF NOT EXISTS idx_inventories_char_item ON inventories(character_id, item_id);

-- Index for cleanup/sync by updated_at
CREATE INDEX IF NOT EXISTS idx_inventories_updated ON inventories(updated_at);

-- ── Equipment ───────────────────────────────────────────────────────────────
-- Equipped items. One row per equipment slot.
CREATE TABLE IF NOT EXISTS equipment (
    id              UUID PRIMARY KEY,
    character_id    UUID NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    equip_slot      INTEGER NOT NULL,
    item_id         VARCHAR(64) NOT NULL,
    item_data       JSONB NOT NULL DEFAULT '{}',   -- full item state (enchants, durability, etc.)
    bound           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (character_id, equip_slot)
);

-- Composite index for "recent equipment changes by character"
CREATE INDEX IF NOT EXISTS idx_equipment_char_created ON equipment(character_id, created_at DESC);

-- Index for "find equipped item by character + item_id"
CREATE INDEX IF NOT EXISTS idx_equipment_char_item ON equipment(character_id, item_id);

-- Index for sync by updated_at
CREATE INDEX IF NOT EXISTS idx_equipment_updated ON equipment(updated_at);

-- ── Migration metadata ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    VARCHAR(128) PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum   VARCHAR(64)
);