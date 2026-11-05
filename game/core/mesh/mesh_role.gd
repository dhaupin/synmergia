## MeshRole - THE MESH ROLE LAW (shard mesh Phase 3).
##
## ONE FILE OWNS WHAT A CONTAINER IS:
##   * shard       -- serves players (a game port; registers with the mesh).
##   * coordinator -- owns the shard registry + cross-shard bus; serves NO
##                    game port and never registers as a shard.
##   * standalone  -- dev/CI: one process that is both.
##
## Resolution is env-only and total, so an unset/unknown combination
## falls back to standalone and a dev boot stays byte-identical.
##
##   START_MODE=coordinator                            -> coordinator
##   SHARD_ID set, or START_MODE prod|headless|server  -> shard
##   otherwise                                         -> standalone
##
## With MESH_AUTOSHARD set and no SHARD_ID, a shard derives its id from
## the container HOSTNAME so `docker compose --scale shard=N` gives each
## replica a unique identity. Unset, the id is shard_1 exactly as before.
##
## No autoload, no collision: static funcs, read by ShardManager (identity)
## and CoordinatorService (bus self id).

extends RefCounted
class_name MeshRole

const ROLE_COORDINATOR := "coordinator"
const ROLE_SHARD := "shard"
const ROLE_STANDALONE := "standalone"

## The coordinator's bus/registry identity. Never a shard id, so the
## registry never mistakes the coordinator for a player-serving node.
const COORDINATOR_ID := "coordinator"

const SHARD_MODES := ["prod", "headless", "server"]
const AUTOSHARD_ENV := "MESH_AUTOSHARD"


static func resolve() -> String:
	var mode := OS.get_environment("START_MODE").strip_edges().to_lower()
	if mode == ROLE_COORDINATOR:
		return ROLE_COORDINATOR
	if OS.get_environment("SHARD_ID").strip_edges() != "":
		return ROLE_SHARD
	if mode in SHARD_MODES:
		return ROLE_SHARD
	return ROLE_STANDALONE


static func is_coordinator() -> bool:
	return resolve() == ROLE_COORDINATOR


## The mesh-wide identity of THIS container on the bus/registry. The
## coordinator is COORDINATOR_ID; a shard is its SHARD_ID.
static func self_id() -> String:
	if is_coordinator():
		return COORDINATOR_ID
	return shard_id()


## The shard id this container runs as. SHARD_ID wins; with MESH_AUTOSHARD
## set and SHARD_ID unset, the container HOSTNAME is used (unique per
## replica under `--scale`); otherwise shard_1 (the dev default).
static func shard_id() -> String:
	var sid := OS.get_environment("SHARD_ID").strip_edges()
	if sid != "":
		return sid
	if _env_truthy(AUTOSHARD_ENV):
		var host := _sanitize(OS.get_environment("HOSTNAME"))
		if host != "":
			return host
	return "shard_1"


## Whether MESH_AUTOSHARD is set (public: ShardManager reads it too).
static func autoshard_enabled() -> bool:
	return _env_truthy(AUTOSHARD_ENV)


static func _env_truthy(name: String) -> bool:
	return OS.get_environment(name).strip_edges().to_lower() in ["1", "true", "yes", "on"]


static func _sanitize(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == "_" or ch == "-":
			out += "_"
	return out
