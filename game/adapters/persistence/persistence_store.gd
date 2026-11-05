extends RefCounted
class_name PersistenceStore

# Base interface for any durable storage backend (Postgres, SQLite,
# in-memory). Services depend on this; concrete backends extend it.
#
# Convention: every method returns an int code (0 = ok) or an
# Array[Dictionary] for queries. Errors propagate as non-zero
# codes or empty arrays, never exceptions.
#
# This is the "abstract" pattern for GDScript. Subclasses MUST
# override every method. The base implementations below just
# push errors so unimplemented stores fail loud at first call.


# --- Connection lifecycle ---

func open(config: Dictionary) -> int:
	push_error("PersistenceStore.connect: not implemented")
	return -1


func close() -> void:
	pass


func healthy() -> bool:
	return false


# --- Query API ---

# Parameterized query. Returns Array[Dictionary], one entry per row,
# keyed by column name. Empty array on no rows or error.
func query(sql: String, params: Array = []) -> Array:
	push_error("PersistenceStore.query: not implemented")
	return []


# Single-row convenience. Returns {} (empty) on no row or error.
func query_one(sql: String, params: Array = []) -> Dictionary:
	var rows := query(sql, params)
	if rows.is_empty():
		return {}
	return rows[0]


# Execute INSERT/UPDATE/DELETE. Returns rows affected. -1 on error.
func execute(sql: String, params: Array = []) -> int:
	push_error("PersistenceStore.execute: not implemented")
	return -1


# --- Transactions ---

func begin() -> int:
	push_error("PersistenceStore.begin: not implemented")
	return -1


func commit(tx_id: int) -> int:
	push_error("PersistenceStore.commit: not implemented")
	return -1


func rollback(tx_id: int) -> int:
	push_error("PersistenceStore.rollback: not implemented")
	return -1


# --- Bulk ---

# Insert many rows in one call. `rows` is Array[Array], each inner
# array is positional values matching `columns`. Returns rows
# inserted, -1 on error.
func insert_many(table: String, rows: Array, columns: Array) -> int:
	push_error("PersistenceStore.insert_many: not implemented")
	return -1


# Multi-statement script (for migrations, seed data, etc.).
# Each entry in `statements` is a String. Returns 0 on full success.
func execute_batch(statements: Array) -> int:
	push_error("PersistenceStore.execute_batch: not implemented")
	return -1


# --- KV Bulk Operations ---

# Set multiple key-value pairs in one call. `entries` is a Dictionary
# mapping keys to values. Returns 0 on success, -1 on error.
func set_many(entries: Dictionary) -> int:
	push_error("PersistenceStore.set_many: not implemented")
	return -1


# Get multiple values by keys in one call. Returns a Dictionary
# mapping keys to their values (missing keys map to null).
func get_many(keys: Array) -> Dictionary:
	push_error("PersistenceStore.get_many: not implemented")
	return {}


# Delete multiple keys in one call. Returns count of deleted keys.
func delete_many(keys: Array) -> int:
	push_error("PersistenceStore.delete_many: not implemented")
	return -1


# --- KV Single-Key Convenience (base implementations) ---
# ~25 services call these directly on the persistence store they get
# from AdapterRegistry.get_persistence(...). They were documented only
# on the DictStore wrapper, so every direct call against a raw backend
# threw "Nonexistent function 'set_kv'" and silently dropped the write.
# Routed through the batch API (prd-db.md section 4) so the kv table
# stays canonical and values round-trip identically across backends.
# Memory/Postgres overrides below keep the same contract.

func set_kv(key: String, value: Variant, _ttl_sec: int = 0) -> void:
	set_many({key: value})


func get_kv(key: String, default: Variant = null) -> Variant:
	var val = get_value(key)
	return val if val != null else default


# Stores the decoded Variant. Backends encode for durability however
# they like (memory: raw column, Postgres: JSON string); get_value
# decodes symmetrically, so callers always get what they put in.
func set_value(key: String, value: Variant, _ttl_sec: int = 0) -> int:
	return set_many({key: value})


func get_value(key: String) -> Variant:
	var result := get_many([key])
	return result.get(key, null)


func delete_value(key: String) -> int:
	return delete_many([key])


func has_key(key: String) -> bool:
	return get_value(key) != null


# All keys currently in the kv table. Backends with a native listing
# (memory) override this; the default rides the portable SQL shim, which
# every SQL backend supports. ~40 services call this on the raw store.
func all_keys() -> Array:
	var keys: Array = []
	for row in query("SELECT key FROM kv", []):
		var k = row.get("key", "")
		if k != "":
			keys.append(k)
	return keys


func erase(key: String) -> void:
	delete_many([key])


func delete(key: String) -> void:
	erase(key)


# --- Transaction context manager ---

# Execute a callable inside a transaction.
# Callable signature: func(tx_id: int) -> int (0 = commit, non-zero = rollback)
# Returns 0 on success (commit), -1 on failure (rollback).
func with_transaction(callable: Callable) -> int:
	push_error("PersistenceStore.with_transaction: not implemented")
	return -1


# Low-level transaction query/execute that accept tx_id.
# These are used inside the callable passed to with_transaction.
func query_tx(sql: String, params: Array, tx_id: int) -> Array:
	push_error("PersistenceStore.query_tx: not implemented")
	return []


func execute_tx(sql: String, params: Array, tx_id: int) -> int:
	push_error("PersistenceStore.execute_tx: not implemented")
	return -1


func insert_many_tx(table: String, rows: Array, columns: Array, tx_id: int) -> int:
	push_error("PersistenceStore.insert_many_tx: not implemented")
	return -1


# --- Shard state atomic commit (Edge Case B) ---

# Atomically commit shard state snapshot + locked seeds + parameter flushes.
# Prevents partial state on crash during finalization.
func commit_shard_state_atomic(shard_id: String, snapshot_data: Dictionary) -> int:
	push_error("PersistenceStore.commit_shard_state_atomic: not implemented")
	return -1


# --- Observability ---

# Returns connection pool and circuit breaker metrics.
# Keys: active_connections (int), pending_queries (int), circuit_breaker_tripped (bool)
func get_metrics() -> Dictionary:
	return {
		"active_connections": 0,
		"pending_queries": 0,
		"circuit_breaker_tripped": false
	}
