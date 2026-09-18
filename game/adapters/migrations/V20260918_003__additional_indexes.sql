-- V20260918_003__additional_indexes.sql
--
-- Additional composite indexes for high-query tables.
-- Addresses IO Bottleneck B: Unindexed spatial & foreign key queries.
-- These indexes are ADDITIVE and do not modify locked schemas.
--
-- Idempotent: wraps every index in CREATE INDEX IF NOT EXISTS.
-- Safe to re-run.

-- ── Characters: spatial + faction lookups ───────────────────────────────────
-- Query: "Find characters in zone for faction" (PvP, world events)
CREATE INDEX IF NOT EXISTS idx_characters_zone_faction
    ON characters(zone_id, faction_id) WHERE deleted_at IS NULL;

-- Query: "Recently active characters" (leaderboards, cleanup)
CREATE INDEX IF NOT EXISTS idx_characters_last_online
    ON characters(last_online DESC) WHERE deleted_at IS NULL;

-- Query: "Characters by account ordered by last login" (character select)
CREATE INDEX IF NOT EXISTS idx_characters_account_last_online
    ON characters(account_id, last_online DESC) WHERE deleted_at IS NULL;

-- ── Sessions: recent sessions by account ────────────────────────────────────
-- Query: "Recent sessions for account" (security audit, device management)
CREATE INDEX IF NOT EXISTS idx_sessions_account_created
    ON sessions(account_id, created_at DESC);

-- ── Agent Actions: recent actions by agent ──────────────────────────────────
-- Query: "Recent actions by agent" (audit, debugging) - already in V20260918_001
-- But adding here as reference for the pattern (character_id if applicable)
-- Note: agent_actions uses agent_id, not character_id. If agent_id maps to character,
-- the index idx_agent_actions_agent_created covers it.

-- ── Inventory/Equipment: additional query patterns ──────────────────────────
-- (Created in V20260918_002__init_inventory.sql, listed here for reference)
-- idx_inventories_char_created ON inventories(character_id, created_at DESC)
-- idx_inventories_char_item ON inventories(character_id, item_id)
-- idx_equipment_char_created ON equipment(character_id, created_at DESC)
-- idx_equipment_char_item ON equipment(character_id, item_id)

-- ── Respawn Points: zone + faction ──────────────────────────────────────────
-- Query: "Respawn points in zone for faction" (death handling)
-- Already created in V20260918_001__init_respawn_points.sql
-- CREATE INDEX idx_respawn_zone_faction ON respawn_points(zone_id, faction_id);

-- ── Future tables (reference - will be created in their own migrations) ──────
-- When creating quest_progress:
--   CREATE INDEX idx_quest_progress_char_status ON quest_progress(character_id, status);
--   CREATE INDEX idx_quest_progress_char_created ON quest_progress(character_id, created_at DESC);
--
-- When creating vaults:
--   CREATE INDEX idx_vaults_char_type ON vaults(character_id, vault_type);
--   CREATE INDEX idx_vaults_char_updated ON vaults(character_id, updated_at DESC);
--
-- When creating guild_members:
--   CREATE INDEX idx_guild_members_guild_rank ON guild_members(guild_id, rank);
--   CREATE INDEX idx_guild_members_char_joined ON guild_members(character_id, joined_at DESC);
--
-- When creating friends:
--   CREATE INDEX idx_friends_char_status ON friends(character_id, status);
--   CREATE INDEX idx_friends_char_created ON friends(character_id, created_at DESC);
--
-- When creating player_waypoints:
--   CREATE INDEX idx_waypoints_char_zone ON player_waypoints(character_id, zone_id);
--   CREATE INDEX idx_waypoints_char_created ON player_waypoints(character_id, created_at DESC);
--
-- When creating death_log:
--   CREATE INDEX idx_death_log_char_created ON death_log(character_id, created_at DESC);
--
-- When creating trade_history:
--   CREATE INDEX idx_trade_history_char_created ON trade_history(character_id, created_at DESC);
--   CREATE INDEX idx_trade_history_partner_created ON trade_history(partner_id, created_at DESC);
--
-- When creating crafting_history:
--   CREATE INDEX idx_crafting_history_char_created ON crafting_history(character_id, created_at DESC);
--
-- When creating transfer_history:
--   CREATE INDEX idx_transfer_history_char_created ON transfer_history(character_id, created_at DESC);

-- ── Migration metadata ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    VARCHAR(128) PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum   VARCHAR(64)
);