-- V20260918_001__init_respawn_points.sql
--
-- Respawn points (ankhs) and agent connectors.
-- Covers RespawnService -> RespawnStore and ConnectorService -> ConnectorStore.
--
-- Idempotent: wraps every table/index in CREATE ... IF NOT EXISTS.
-- Safe to re-run.

-- ── Respawn Points (Ankhs) ──────────────────────────────────────────────────
-- Static world data. Mirrors ankh.gd exports. Backing store: RespawnStore.
-- Hot reads go through Redis cache (player death to nearest ankh).
CREATE TABLE IF NOT EXISTS respawn_points (
    id              TEXT PRIMARY KEY,
    zone_id         TEXT NOT NULL REFERENCES zones(id),
    name            TEXT NOT NULL,
    position        VECTOR3 NOT NULL,
    faction_id      TEXT REFERENCES factions(id),
    bind_cost       INTEGER DEFAULT 0,
    cooldowns       JSONB DEFAULT '{}',
    enabled         BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Composite index for zone+faction lookups (common query: "find respawn points in zone for faction")
CREATE INDEX IF NOT EXISTS idx_respawn_zone_faction ON respawn_points(zone_id, faction_id);

-- Individual indexes for single-column lookups
CREATE INDEX IF NOT EXISTS idx_respawn_zone ON respawn_points(zone_id);
CREATE INDEX IF NOT EXISTS idx_respawn_faction ON respawn_points(faction_id) WHERE faction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_respawn_enabled ON respawn_points(enabled) WHERE enabled;

-- ── Agent Connectors ────────────────────────────────────────────────────────
-- Configuration for external agent connectors (Discord, Webhook, MCP, etc.)
-- Runtime session state in ConnectorService._connected_agents (in-memory).
-- Durable audit trail in ConnectorStore (Postgres).
CREATE TABLE IF NOT EXISTS agent_connectors (
    id              TEXT PRIMARY KEY,
    connector_type  TEXT NOT NULL,
    config          JSONB NOT NULL,
    permissions     JSONB DEFAULT '[]',
    audit_log       BOOLEAN DEFAULT TRUE,
    enabled         BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_connectors_type ON agent_connectors(connector_type);
CREATE INDEX IF NOT EXISTS idx_agent_connectors_enabled ON agent_connectors(enabled) WHERE enabled;

-- ── Agent Actions (Audit Log) ───────────────────────────────────────────────
-- Every action taken by an agent connector. High-volume append-only table.
-- Indexed by (agent_id, created_at DESC) for "recent actions by agent" queries.
CREATE TABLE IF NOT EXISTS agent_actions (
    id              BIGSERIAL PRIMARY KEY,
    agent_id        TEXT NOT NULL,
    connector_id    TEXT NOT NULL REFERENCES agent_connectors(id),
    action_type     TEXT NOT NULL,
    payload         JSONB NOT NULL,
    response        JSONB,
    approved_by     TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Composite index for the most common query: recent actions by agent_id
CREATE INDEX IF NOT EXISTS idx_agent_actions_agent_created ON agent_actions(agent_id, created_at DESC);

-- Supporting indexes for other query patterns
CREATE INDEX IF NOT EXISTS idx_agent_actions_connector ON agent_actions(connector_id);
CREATE INDEX IF NOT EXISTS idx_agent_actions_type ON agent_actions(action_type);
CREATE INDEX IF NOT EXISTS idx_agent_actions_approved ON agent_actions(approved_by) WHERE approved_by IS NOT NULL;

-- ── Migration metadata ───────────────────────────────────────────────────────
-- Tracks which migrations have been applied so the runner can skip on boot.
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    VARCHAR(128) PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum   VARCHAR(64)
);