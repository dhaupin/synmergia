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
