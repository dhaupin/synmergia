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

func connect(config: Dictionary) -> int:
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
