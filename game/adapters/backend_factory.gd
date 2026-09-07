extends Node

# BackendFactory -- wires concrete adapters into the registry
# based on env-driven backend selection.
#
# Called once at boot by AdapterRegistry or by the game's main
# scene. Reads:
#   STORAGE_BACKEND = "memory" | "postgres"   (default: memory)
#   CACHE_BACKEND   = "memory" | "redis"     (default: memory)
#   PG_BRIDGE_URL   = http://pg-bridge:8080
#   REDIS_BRIDGE_URL = http://redis-bridge:8080
#
# Until the pg-bridge / redis-bridge sidecars exist, only the
# memory backends will successfully connect. The Postgres and
# Redis adapters are real and complete -- they just need a
# running sidecar to talk to.
#
# Manifest: which store names get registered and with what
# backing service. Add new entries here when wiring a new store.
#
# See prd-db.md sec.5, sec.8.


# Concrete adapter impls are referenced via global class_name
# (registered by their `class_name X` line in each file).
# The base interfaces (PersistenceStore / CacheStore / MemoryStore)
# are also global class_names, so we don't need to preload them.
const MigrationRunner = preload("res://adapters/migrations/migration_runner.gd")

# Store name -> which service consumes it. Just a comment map for now;
# the real wiring happens when each service calls AdapterRegistry at runtime.
const STORE_MANIFEST := {
	# Persistence stores (durable)
	"accounts": "AccountService, LoginService",
	"sessions": "LoginService",
	"characters": "PlayerManager, character_select, lobby",
	"inventories": "InventoryService, SlotService",
	"equipment": "InventoryService, SlotService",
	"vaults": "VaultService, SlotService",
	"guilds": "GuildService",
	"guild_roster": "GuildService",
	"friends": "FriendsService",
	"blocks": "FriendsService",
	"parties": "PartyService",
	"loot_history": "LootService",
	"loot_tables": "LootService",
	"chat_log": "ChatService",
	"votes": "CommunityGovernance",
	"proposals": "CommunityGovernance",
	"factions": "FactionManager",
	"player_waypoints": "WaypointService",
	"zones": "ZoneManager",
	"spawn_definitions": "SpawnService",
	"trade_history": "TradeService, VendorService",
	"crafting_recipes": "BlacksmithService",
	"skills": "SkillAcademyService",
	"player_skills": "SkillAcademyService",
	"achievements": "AchievementService",
	"player_achievements": "AchievementService",
	"titles": "TitleService",
	"player_titles": "TitleService",
	"bans": "SecurityService",
	"mutes": "SecurityService",
	"security_log": "SecurityService",
	"anticheat_events": "AntiCheatService",
	"auto_responses": "AutoResponseService",
	"transfers": "SameAccountTransferService",
	"respawn_points": "RespawnService",
	"death_log": "DeathFeatures",
	"fairness_metrics": "FairnessService",
	"entities": "EntityService",
	"world_state": "WorldService",
	"world_events": "WorldService",
	"world_event_instances": "WorldService",
	"shards": "ShardManager",
	"servers": "ServerManager",
	"game_data": "DataService (templates)",
	"matchmaking_queue": "MatchmakingQoS",
	"dialogues": "DialogService",
	"agent_connectors": "ConnectorService",
	"agent_actions": "ConnectorService",
	"player_settings": "PlayerConfig",
	"npc_offerings": "VendorService",
	"container_configs": "SlotService",
	"target_schemas": "TargetingManager",
	"species": "DataService",
	# Cache stores (ephemeral, TTL)
	"online_status": "FriendsService, ShardManager",
	"rate_limits": "LoginService, QoSService",
	"cooldowns": "CooldownService",
	"session_cache": "LoginService",
	"item_cache": "InventoryService",
	"guild_cache": "GuildService",
	"zone_cache": "ZoneManager",
	"event_subscriptions": "EventHub",
	# Memory stores (process-local, no cross-process)
	"active_loot": "LootService",
	"active_follows": "FollowService",
	"active_wars": "FactionManager",
	"active_revives": "RespawnService",
	"active_waypoints": "WaypointService",
	"active_trades": "TradeService",
	"active_locks": "PlayerLockService",
	"active_dialogue": "DialogService",
	"anti_cheat_profiles": "AntiCheatService",
	"connected_agents": "ConnectorService",
}


func _ready() -> void:
	boot_defaults()


# Look up the AdapterRegistry autoload by path. We don't use the bare
# `AdapterRegistry` identifier so the file parses cleanly in --script
# mode (where autoloads are not pre-loaded). At runtime the autoload
# is mounted at /root/AdapterRegistry by project.godot.
func _registry() -> Node:
	if get_tree() == null:
		return null
	return get_tree().root.get_node_or_null("AdapterRegistry")


# Same indirection pattern for GameLog. Bare-identifier autoload
# references fail to parse in --script mode.
func _log_info(msg: String) -> void:
	var gl = get_tree().root.get_node_or_null("GameLog") if get_tree() else null
	if gl and gl.has_method("info"):
		gl.info(msg)
	else:
		print(msg)


# Wire up the default set of stores. Services that need their
# own store (e.g. login_rate_limit) can call register_cache()
# directly with a MemoryCacheStore.
func boot_defaults() -> void:
	var storage_backend := OS.get_environment("STORAGE_BACKEND")
	if storage_backend == "":
		storage_backend = "memory"

	var cache_backend := OS.get_environment("CACHE_BACKEND")
	if cache_backend == "":
		cache_backend = "memory"

	# Persistence stores
	var persistence_store = _make_persistence(storage_backend)
	if persistence_store == null:
		push_error("BackendFactory: STORAGE_BACKEND=%s not supported, falling back to memory" % storage_backend)
		persistence_store = _make_persistence("memory")

	var reg := _registry()
	if reg == null:
		push_error("BackendFactory: AdapterRegistry autoload not found")
		return

	# Register all persistence store names with the same backing.
	for store_name in STORE_MANIFEST:
		# Skip cache-only and memory-only entries.
		if _is_cache_only(store_name) or _is_memory_only(store_name):
			continue
		reg.register_persistence(store_name, persistence_store)

	# Run schema migrations against the persistence backend (blocking
	# at boot per prd-db.md sec.9.2). Memory backend: migrations are
	# applied in-memory (harmless, and lets dev boot exercise the runner).
	# Postgres backend: creates tables in the real DB.
	var runner := MigrationRunner.new()
	var mig_rc := runner.run(persistence_store, null)
	if mig_rc != 0:
		push_error("BackendFactory: migration runner failed (rc=%d)" % mig_rc)

	# Cache stores
	var cache_store = _make_cache(cache_backend)
	if cache_store == null:
		push_error("BackendFactory: CACHE_BACKEND=%s not supported, falling back to memory" % cache_backend)
		cache_store = _make_cache("memory")

	for store_name in STORE_MANIFEST:
		if not _is_cache_only(store_name):
			continue
		reg.register_cache(store_name, cache_store)

	# Memory stores -- always in-memory, no backend choice.
	for store_name in STORE_MANIFEST:
		if not _is_memory_only(store_name):
			continue
		var mem := MemoryStore.new()
		reg.register_memory(store_name, mem)

	_log_info("BackendFactory: persistence=%s cache=%s" % [storage_backend, cache_backend])


func _make_persistence(backend: String) -> PersistenceStore:
	match backend:
		"memory":
			var s := MemoryPersistenceStore.new()
			s.open({})
			return s
		"postgres":
			var s := PostgresStore.new()
			var url := OS.get_environment("PG_BRIDGE_URL")
			if url == "":
				url = "http://localhost:8080"
			var rc := s.open({"bridge_url": url})
			if rc != 0:
				return null
			return s
	return null


func _make_cache(backend: String) -> CacheStore:
	match backend:
		"memory":
			var s := MemoryCacheStore.new()
			s.open({})
			return s
		"redis":
			var s := RedisStore.new()
			var url := OS.get_environment("REDIS_BRIDGE_URL")
			if url == "":
				url = "http://localhost:8081"
			var rc := s.open({"bridge_url": url})
			if rc != 0:
				return null
			return s
	return null


func _is_cache_only(name: String) -> bool:
	return name in [
		"online_status", "rate_limits", "cooldowns", "session_cache",
		"item_cache", "guild_cache", "zone_cache", "event_subscriptions",
	]


func _is_memory_only(name: String) -> bool:
	return name in [
		"active_loot", "active_follows", "active_wars", "active_revives",
		"active_waypoints", "active_trades", "active_locks", "active_dialogue",
		"anti_cheat_profiles", "connected_agents",
	]
