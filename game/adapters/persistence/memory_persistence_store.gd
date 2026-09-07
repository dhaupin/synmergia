extends PersistenceStore
class_name MemoryPersistenceStore

# In-memory implementation of PersistenceStore.
#
# Maintains tables as Dictionary[String, Array[Dictionary]] where
# each row is a Dict keyed by column name. Supports a useful subset
# of SQL for tests and dev/offline mode:
#
#   SELECT * FROM table
#   SELECT * FROM table WHERE col = $1
#   SELECT * FROM table WHERE col = $1 AND col2 = $2
#   INSERT INTO table (col1, col2) VALUES ($1, $2)
#   UPDATE table SET col1 = $1 WHERE col = $2
#   DELETE FROM table WHERE col = $1
#
# NOT a full SQL engine. Don't expect JOINs, GROUP BY, ORDER BY.
# Use it for tests + dev, swap to PostgresStore for production.
#
# Transactions are no-ops here but the API is preserved so callers
# can be backend-agnostic.


var _tables: Dictionary = {}  # table_name -> Array[Dictionary]
var _tx_counter: int = 0
var _active_tx: Dictionary = {}  # tx_id -> { snapshot: Dictionary, undo_log: Array }


func connect(config: Dictionary) -> int:
	_tables = {}
	_tx_counter = 0
	_active_tx = {}
	return 0


func close() -> void:
	_tables.clear()
	_active_tx.clear()


func healthy() -> bool:
	return true


# Reset state between tests. Not part of the interface.
func reset() -> void:
	connect({})


# --- Query API ---

func query(sql: String, params: Array = []) -> Array:
	var s := sql.strip_edges()
	var upper := s.to_upper()
	if upper.begins_with("SELECT"):
		return _query_select(s, params)
	# Other SELECT-like queries (SHOW, EXPLAIN) -> empty.
	if upper.begins_with("INSERT") or upper.begins_with("UPDATE") or upper.begins_with("DELETE"):
		push_warning("MemoryPersistenceStore: use execute() for write queries, got: " + s)
		return []
	return []


func execute(sql: String, params: Array = []) -> int:
	var s := sql.strip_edges()
	var upper := s.to_upper()
	if upper.begins_with("INSERT"):
		return _exec_insert(s, params)
	if upper.begins_with("UPDATE"):
		return _exec_update(s, params)
	if upper.begins_with("DELETE"):
		return _exec_delete(s, params)
	push_warning("MemoryPersistenceStore: unrecognized statement: " + s)
	return -1


# --- Transactions (no-ops for in-memory, API preserved) ---

func begin() -> int:
	_tx_counter += 1
	# Take a shallow snapshot for rollback.
	var snapshot: Dictionary = {}
	for table_name in _tables.keys():
		snapshot[table_name] = (_tables[table_name] as Array).duplicate(true)
	_active_tx[_tx_counter] = {"snapshot": snapshot, "undo_log": []}
	return _tx_counter


func commit(tx_id: int) -> int:
	if not _active_tx.has(tx_id):
		return -1
	_active_tx.erase(tx_id)
	return 0


func rollback(tx_id: int) -> int:
	if not _active_tx.has(tx_id):
		return -1
	var snapshot: Dictionary = _active_tx[tx_id]["snapshot"]
	_tables = snapshot
	_active_tx.erase(tx_id)
	return 0


# --- Bulk ---

func insert_many(table: String, rows: Array, columns: Array) -> int:
	if not _tables.has(table):
		_tables[table] = []
	var t: Array = _tables[table]
	var n := 0
	for row in rows:
		var entry: Dictionary = {}
		for i in range(columns.size()):
			if i < (row as Array).size():
				entry[columns[i]] = row[i]
		t.append(entry)
		n += 1
	return n


func execute_batch(statements: Array) -> int:
	for stmt in statements:
		var r := execute(stmt, [])
		if r < 0:
			return r
	return 0


# --- Internal SQL shim ---
# Deliberately minimal. Real Postgres handles the hard cases.

func _query_select(sql: String, params: Array) -> Array:
	# Parse: SELECT <cols> FROM <table> [WHERE <col> = $1 [AND <col2> = $2]]
	# No support for SELECT *, comma-lists, etc. We do best-effort.
	var from_idx := sql.find("FROM")
	if from_idx < 0:
		return []
	var after_from := sql.substr(from_idx + 4).strip_edges()
	var where_idx := after_from.find(" WHERE ")
	var table: String
	var where_clause: String = ""
	if where_idx < 0:
		table = after_from.strip_edges()
	else:
		table = after_from.substr(0, where_idx).strip_edges()
		where_clause = after_from.substr(where_idx + 7).strip_edges()

	if not _tables.has(table):
		return []
	var rows: Array = (_tables[table] as Array).duplicate()

	if where_clause != "":
		var conds := _parse_where(where_clause)
		rows = rows.filter(func(row): return _match_conds(row, conds, params))
	return rows


func _exec_insert(sql: String, params: Array) -> int:
	# INSERT INTO table (col1, col2) VALUES ($1, $2)
	var into_idx := sql.find("INTO")
	if into_idx < 0:
		return -1
	var rest := sql.substr(into_idx + 4).strip_edges()
	# Skip the "INSERT" prefix and "INTO" keyword; find the first paren.
	var paren_open := rest.find("(")
	if paren_open < 0:
		return -1
	var table := rest.substr(0, paren_open).strip_edges()
	var after_cols := rest.substr(paren_open + 1)
	var paren_close := after_cols.find(")")
	if paren_close < 0:
		return -1
	var cols_str := after_cols.substr(0, paren_close)
	var columns := _split_csv(cols_str)
	if not _tables.has(table):
		_tables[table] = []
	var t: Array = _tables[table]
	var entry: Dictionary = {}
	for i in range(columns.size()):
		if i < params.size():
			entry[columns[i]] = params[i]
	t.append(entry)
	return 1


func _exec_update(sql: String, params: Array) -> int:
	# UPDATE table SET col1 = $1, col2 = $2 WHERE col = $3
	# Params: [v1, v2, v3] -- but $1 and $2 share the front of the array.
	# We split params: leading SET values, then WHERE values.
	var upper := sql.strip_edges().to_upper()
	if not upper.begins_with("UPDATE"):
		return -1
	# Strip the "UPDATE" prefix.
	var rest := sql.strip_edges().substr(6).strip_edges()
	# Parse table name (next token).
	var space_idx := rest.find(" ")
	if space_idx < 0:
		return -1
	var table := rest.substr(0, space_idx).strip_edges()
	var after_table := rest.substr(space_idx + 1).strip_edges()
	# after_table starts with "SET ..."
	if not after_table.to_upper().begins_with("SET"):
		return -1
	var set_rest := after_table.substr(3).strip_edges()
	var where_idx := set_rest.find(" WHERE ")
	if where_idx < 0:
		where_idx = set_rest.find(" where ")
	if where_idx < 0:
		return -1
	var set_str := set_rest.substr(0, where_idx).strip_edges()
	var where_str := set_rest.substr(where_idx + 7).strip_edges()

	if not _tables.has(table):
		return 0
	var t: Array = _tables[table]

	# Parse SET: col1 = $1, col2 = $2 -> [(col1, 0), (col2, 1)] (indices into SET values)
	var set_pairs := _parse_set(set_str)
	var set_count := set_pairs.size()
	# First `set_count` params are SET values, remainder are WHERE values.
	var where_conds := _parse_where(where_str)
	var where_params := params.slice(set_count)

	var updated := 0
	for row in t:
		if _match_conds(row, where_conds, where_params):
			for pair in set_pairs:
				var col: String = pair[0]
				var set_idx_in_params: int = pair[1]
				if set_idx_in_params < set_count:
					row[col] = params[set_idx_in_params]
			updated += 1
	return updated


func _exec_delete(sql: String, params: Array) -> int:
	# DELETE FROM table WHERE col = $1
	var from_idx := sql.find("FROM")
	if from_idx < 0:
		return -1
	var rest := sql.substr(from_idx + 4).strip_edges()
	var where_idx := rest.find(" WHERE ")
	if where_idx < 0:
		# DELETE FROM table -- nuke it.
		var table := rest.strip_edges()
		if not _tables.has(table):
			return 0
		var n := (_tables[table] as Array).size()
		_tables.erase(table)
		return n
	var table2 := rest.substr(0, where_idx).strip_edges()
	var where_str := rest.substr(where_idx + 7).strip_edges()
	if not _tables.has(table2):
		return 0
	var t: Array = _tables[table2]
	var conds := _parse_where(where_str)
	var initial_size := t.size()
	_tables[table2] = t.filter(func(row): return not _match_conds(row, conds, params))
	return initial_size - (_tables[table2] as Array).size()


# --- Parsing helpers ---

# Parses "col = $1 AND col2 = $2" -> [{col: "col", param: 0}, ...]
# Param is the 0-based index into the params array.
func _parse_where(clause: String) -> Array:
	var conds: Array = []
	# Split on AND
	var parts := clause.split(" AND ", false)
	for p in parts:
		var pp: String = p.strip_edges()
		var eq := pp.find("=")
		if eq < 0:
			continue
		var col := pp.substr(0, eq).strip_edges()
		var rhs := pp.substr(eq + 1).strip_edges()
		if rhs.begins_with("$"):
			var idx_str := rhs.substr(1)
			var idx := -1
			if idx_str.is_valid_int():
				idx = idx_str.to_int() - 1
			conds.append({"col": col, "param": idx})
	return conds


func _match_conds(row: Dictionary, conds: Array, params: Array) -> bool:
	for c in conds:
		var col: String = c["col"]
		var idx: int = c["param"]
		if idx < 0 or idx >= params.size():
			return false
		if row.get(col) != params[idx]:
			return false
	return true


# Parses "col1 = $1, col2 = $2" -> [["col1", 0], ["col2", 1]]
func _parse_set(clause: String) -> Array:
	var pairs: Array = []
	for p in clause.split(","):
		var pp: String = p.strip_edges()
		var eq := pp.find("=")
		if eq < 0:
			continue
		var col := pp.substr(0, eq).strip_edges()
		var rhs := pp.substr(eq + 1).strip_edges()
		if rhs.begins_with("$"):
			var idx_str := rhs.substr(1)
			var idx := -1
			if idx_str.is_valid_int():
				idx = idx_str.to_int() - 1
			pairs.append([col, idx])
	return pairs


func _split_csv(s: String) -> Array:
	var out: Array = []
	for p in s.split(","):
		out.append(p.strip_edges())
	return out


# --- Test/dev helpers (not in interface) ---

func seed(table: String, rows: Array) -> void:
	_tables[table] = rows.duplicate(true)


func table_names() -> Array:
	return _tables.keys()


func row_count(table: String) -> int:
	if not _tables.has(table):
		return 0
	return (_tables[table] as Array).size()
