extends "res://adapters/persistence/persistence_store.gd"
class_name MemoryPersistenceStore

# In-memory implementation of PersistenceStore.
#
# Maintains tables as Dictionary[String, Array[Dictionary]] where
# each row is a Dict keyed by column name. Supports a useful subset
# of SQL for tests and dev/offline mode:
#
#   SELECT * FROM table
#   SELECT col1, col2 FROM table
#   SELECT * FROM table WHERE col = $1
#   SELECT * FROM table WHERE col = $1 AND col2 = $2
#   SELECT * FROM table WHERE col = $1 OR col2 = $2
#   SELECT * FROM table WHERE col > $1, <, <=, >=, !=, LIKE
#   SELECT * FROM t1 INNER JOIN t2 ON t1.col = t2.col
#   SELECT * FROM t1 LEFT JOIN t2 ON t1.col = t2.col
#   SELECT id FROM table WHERE col IN ($1, $2)
#   SELECT id FROM table WHERE col IN (SELECT ...)
#   INSERT INTO table (col1, col2) VALUES ($1, $2)
#   INSERT INTO table (col1, col2) VALUES ($1, $2) ON CONFLICT DO NOTHING
#   UPDATE table SET col1 = $1 WHERE col = $2
#   DELETE FROM table WHERE col = $1
#   SELECT ... FROM ... WHERE ... ORDER BY col [ASC|DESC]
#   SELECT ... FROM ... WHERE ... GROUP BY col
#   SELECT ... FROM ... WHERE ... LIMIT N
#
# Not a full SQL engine. Best-effort implementation for tests & dev.
# Swap to PostgresStore for production.
#
# Transactions are no-ops here but the API is preserved so callers
# can be backend-agnostic.


var _tables: Dictionary = {}
var _tx_counter: int = 0
var _active_tx: Dictionary = {}  # tx_id -> { snapshot: Dictionary, undo_log: Array }


func open(config: Dictionary) -> int:
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
	open({})


# --- Query API ---

func query(sql: String, params: Array = []) -> Array:
	var s := sql.strip_edges()
	var upper := s.to_upper()
	if upper.begins_with("SELECT"):
		return _query_select(s, params)
	if upper.begins_with("SHOW") or upper.begins_with("EXPLAIN"):
		return []
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
	if upper.begins_with("CREATE"):
		return _exec_create_table(s)
	if upper.begins_with("DROP"):
		return _exec_drop_table(s)
	if upper.begins_with("ALTER"):
		return 0  # no constraints in memory; schema-only no-op
	push_warning("MemoryPersistenceStore: unrecognized statement: " + s)
	return -1


## DDL: the memory engine models tables as row arrays. CREATE TABLE
## (with or without IF NOT EXISTS) creates an empty table; indexes and
## triggers are no-ops. Required by the migration runner's bootstrap
## (schema_migrations) and by migrations run against the memory backend
## at boot (prd-db.md sec. 9.2).
func _exec_create_table(sql: String) -> int:
	var rest := sql.substr(6, sql.length() - 6).strip_edges()  # past CREATE
	var rest_upper := rest.to_upper()
	if rest_upper.begins_with("INDEX") or rest_upper.begins_with("UNIQUE") or rest_upper.begins_with("TRIGGER"):
		return 0  # meaningless in memory
	var pos := rest_upper.find("TABLE")
	if pos < 0:
		push_warning("MemoryPersistenceStore: unsupported CREATE: " + sql)
		return -1
	rest = rest.substr(pos + 5, rest.length() - pos - 5).strip_edges()
	if rest.to_upper().begins_with("IF NOT EXISTS"):
		rest = rest.substr(13, rest.length() - 13).strip_edges()
	var name := rest.split(" ")[0].strip_edges()
	if name.is_empty():
		push_warning("MemoryPersistenceStore: CREATE TABLE with no table name: " + sql)
		return -1
	if not _tables.has(name):
		_tables[name] = []
	return 0


func _exec_drop_table(sql: String) -> int:
	var rest := sql.substr(4, sql.length() - 4).strip_edges()  # past DROP
	if rest.to_upper().begins_with("INDEX"):
		return 0
	var pos := rest.to_upper().find("TABLE")
	if pos < 0:
		push_warning("MemoryPersistenceStore: unsupported DROP: " + sql)
		return -1
	rest = rest.substr(pos + 5, rest.length() - pos - 5).strip_edges()
	if rest.to_upper().begins_with("IF EXISTS"):
		rest = rest.substr(9, rest.length() - 9).strip_edges()
	var name := rest.split(" ")[0].strip_edges()
	if not name.is_empty():
		_tables.erase(name)
	return 0


func query_one(sql: String, params: Array = []) -> Dictionary:
	var rows := query(sql, params)
	if rows.is_empty():
		return {}
	return rows[0]


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


# --- KV batch API (prd-db.md section 4) ---
# The reference backend must satisfy the full PersistenceStore interface.
# DictStore routes its values through these methods (JSON-encoded).

func set_many(entries: Dictionary) -> int:
	if not _tables.has("kv"):
		_tables["kv"] = []
	var t: Array = _tables["kv"]
	for key in entries.keys():
		var val = entries[key]
		var updated := false
		for row in t:
			if row is Dictionary and row.get("key", "") == key:
				row["value"] = str(val)
				updated = true
				break
		if not updated:
			t.append({"key": key, "value": str(val)})
	return 0


func get_many(keys: Array) -> Dictionary:
	var result: Dictionary = {}
	for key in keys:
		result[key] = null
	if not _tables.has("kv"):
		return result
	for row in _tables["kv"]:
		if row is Dictionary and result.has(row.get("key", "")):
			result[row["key"]] = row.get("value", null)
	return result


func delete_many(keys: Array) -> int:
	var n := 0
	if not _tables.has("kv"):
		return 0
	var remaining: Array = []
	for row in _tables["kv"]:
		if row is Dictionary and keys.has(row.get("key", "")):
			n += 1
		else:
			remaining.append(row)
	_tables["kv"] = remaining
	return n


# --- KV single-key API ---
# Services call these directly on the persistence store (see
# account_service._ready, follow_service, vault_service, etc). They
# route through the batch API above so the kv table stays canonical.

func set_value(key: String, value) -> int:
	return set_many({key: value})


func get_value(key: String):
	var result := get_many([key])
	return result.get(key, null)


func delete_value(key: String) -> int:
	return delete_many([key])


func has_key(key: String) -> bool:
	return get_value(key) != null


func all_keys() -> Array:
	var keys: Array = []
	if not _tables.has("kv"):
		return keys
	for row in _tables["kv"]:
		if row is Dictionary and row.has("key"):
			keys.append(row["key"])
	return keys


func key_count() -> int:
	return all_keys().size()


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
	# Supports: * or column list, basic WHERE with AND/OR, JOINs, WHERE with >, <, !=, LIKE,
	# IN (...) literal lists, IN (SELECT ...), ORDER BY, GROUP BY, LIMIT
	var upper := sql.to_upper()
	var select_start := 0
	var select_upper := upper.find("SELECT")
	if select_upper < 0:
		return []
	select_start = sql.find("SELECT")
	# Skip only whitespace after SELECT. Skipping ALL non-alpha chars was
	# wrong: for "SELECT * FROM t" it jumped past the '*' into "FROM",
	# producing a garbage column list and always-empty projections.
	var pos: int = select_start + 6
	while pos < sql.length() and sql.unicode_at(pos) == 32:
		pos += 1
	select_start = pos
	
	var from_upper := upper.find("FROM")
	if from_upper < 0:
		return []
	
	var select_part := sql.substr(select_start, from_upper - select_start).strip_edges()
	var columns := _parse_column_list(select_part)
	
	var after_from_start := from_upper + 4
	while after_from_start < sql.length() and not _is_alpha(sql.unicode_at(after_from_start)):
		after_from_start += 1
	if after_from_start >= sql.length():
		return []
	
	var rest := sql.substr(after_from_start).strip_edges()
	
	# Parse FROM with possible JOINs
	var joins: Array = []
	var base_table: String = ""
	var tables_result := _parse_from_with_joins(rest, joins)
	if tables_result.is_empty():
		return []
	base_table = tables_result[0]
	
	if not _tables.has(base_table):
		return []
	
	var all_rows: Array = (_tables[base_table] as Array).duplicate(true)
	
	for join_info in joins:
		var join_table: String = join_info[0]
		var join_type: String = join_info[1]
		var join_condition: String = join_info[2]
		var join_rows: Array = (_tables.get(join_table, []) as Array)
		
		if join_type == "INNER":
			all_rows = _apply_inner_join(all_rows, join_rows, join_condition, params)
		elif join_type == "LEFT":
			all_rows = _apply_left_join(all_rows, join_rows, join_condition, params)
	
	# Parse WHERE, ORDER BY, GROUP BY, LIMIT
	var where_idx := rest.find(" WHERE ")
	if where_idx < 0:
		where_idx = rest.find(" where ")
	var where_clause: String = ""
	var order_by_idx := -1
	var group_by_idx := -1
	var limit_idx := -1
	
	if where_idx >= 0:
		var after_where := rest.substr(where_idx + 7).strip_edges()
		# Find WHERE clause end (before ORDER BY, GROUP BY, or LIMIT)
		var where_end := after_where.length()
		for kw in [" ORDER BY", " order by", " GROUP BY", " group by", " LIMIT", " limit"]:
			var kw_idx := after_where.find(kw)
			if kw_idx >= 0 and kw_idx < where_end:
				where_end = kw_idx
		where_clause = after_where.substr(0, where_end).strip_edges()
		order_by_idx = after_where.find(" ORDER BY")
		if order_by_idx < 0:
			order_by_idx = after_where.find(" order by")
		group_by_idx = after_where.find(" GROUP BY")
		if group_by_idx < 0:
			group_by_idx = after_where.find(" group by")
		limit_idx = after_where.find(" LIMIT")
		if limit_idx < 0:
			limit_idx = after_where.find(" limit")
	
	# Apply WHERE conditions
	if where_clause != "" and not all_rows.is_empty():
		var conds := _parse_where_full(where_clause, params)
		all_rows = all_rows.filter(func(row): return _match_conds_full(row, conds, params))
	
	# Apply GROUP BY
	var group_by_cols: Array = []
	if group_by_idx >= 0:
		var group_part := rest.substr(where_idx + 7 + group_by_idx + 9).strip_edges()
		var where_limit_pos := group_part.find(" WHERE ")
		if where_limit_pos >= 0:
			group_part = group_part.substr(0, where_limit_pos)
		group_by_cols = _split_csv(group_part)
		all_rows = _apply_group_by(all_rows, group_by_cols, params)
	
	# Apply ORDER BY
	var order_info: Array = []
	if order_by_idx >= 0:
		var order_part := rest.substr(where_idx + 7 + order_by_idx + 9).strip_edges()
		var where_limit_pos := order_part.find(" WHERE ")
		if where_limit_pos >= 0:
			order_part = order_part.substr(0, where_limit_pos)
		var group_limit_pos := order_part.find(" GROUP BY")
		if group_limit_pos >= 0:
			order_part = order_part.substr(0, group_limit_pos)
		order_info = _parse_order_by(order_part, params)
		all_rows = _apply_order_by(all_rows, order_info)
	
	# Apply LIMIT
	var limit_val: int = -1
	if limit_idx >= 0:
		var limit_part := rest.substr(where_idx + 7 + limit_idx + 7).strip_edges()
		var num_str := ""
		for c in limit_part:
			var char_code := c.unicode_at(0)
			if char_code >= 48 and char_code <= 57:
				num_str += c
			else:
				break
		if num_str.length() > 0:
			limit_val = num_str.to_int()
		all_rows = all_rows.slice(0, limit_val)
	
	# Filter columns
	if columns.size() == 1 and columns[0] == "*":
		return all_rows
	
	var result: Array = []
	for row in all_rows:
		var filtered: Dictionary = {}
		for col in columns:
			if row.has(col):
				filtered[col] = row[col]
		result.append(filtered)
	return result


func _parse_column_list(s: String) -> Array:
	if s == "*":
		return ["*"]
	var out: Array = []
	for part in s.split(","):
		out.append(part.strip_edges())
	return out


func _parse_from_with_joins(sql: String, joins: Array) -> Array:
	# `sql` is the text AFTER the FROM keyword (the caller strips it).
	# Re-searching for "FROM" here always returned -1, which made every
	# SELECT against the memory backend return an empty result set.
	var after_from := sql.strip_edges()
	
	var tables: Array = []
	var current_pos := after_from
	
	while current_pos.length() > 0:
		var table_name := ""
		var join_type := ""
		var join_condition := ""
		
		# Check for JOIN keywords
		var join_pos := current_pos.to_upper().find(" JOIN ")
		var left_join_pos := current_pos.to_upper().find(" LEFT JOIN ")
		var inner_join_pos := current_pos.to_upper().find(" INNER JOIN ")
		
		if left_join_pos >= 0:
			join_type = "LEFT"
			join_pos = left_join_pos
		elif inner_join_pos >= 0:
			join_type = "INNER"
			join_pos = inner_join_pos
		elif join_pos >= 0:
			join_type = "INNER"
			
		if join_pos >= 0:
			# Extract table name before JOIN
			table_name = current_pos.substr(0, join_pos).strip_edges()
			var after_join := current_pos.substr(join_pos + 6).strip_edges()
			
			# Find ON condition
			var on_idx := after_join.to_upper().find(" ON ")
			if on_idx >= 0:
				join_condition = after_join.substr(on_idx + 4).strip_edges()
				# Get join table name (between JOIN and ON)
				var join_table_part := after_join.substr(0, on_idx).strip_edges()
				if join_type == "LEFT":
					# Skip "LEFT" keyword
					join_table_part = join_table_part.substr(5).strip_edges()
					
				# The table after JOIN is our join table
				var join_table_end := join_table_part.find(" ")
				if join_table_end < 0:
					join_table_end = join_table_part.length()
				var join_table_name := join_table_part.substr(0, join_table_end).strip_edges()
				joins.append([join_table_name, join_type, join_condition])
			
			# Update current_pos for next iteration
			current_pos = after_join.substr(on_idx + 4 + join_condition.length()).strip_edges()
			continue
			
		# No more JOINs: this is the base table. Stop at the first clause
		# keyword (WHERE/ORDER BY/GROUP BY/LIMIT) -- everything after it
		# belongs to those clauses, not the table name.
		var clause_upper: String = current_pos.to_upper()
		var table_end: int = current_pos.length()
		for kw in [" WHERE ", " WHERE", " ORDER BY", " GROUP BY", " LIMIT"]:
			var kw_i: int = clause_upper.find(kw)
			if kw_i >= 0 and kw_i < table_end:
				table_end = kw_i
		table_name = current_pos.substr(0, table_end).strip_edges()
		tables.append(table_name)
		break
		
	return tables


func _apply_inner_join(left_rows: Array, right_rows: Array, condition: String, params: Array) -> Array:
	var result: Array = []
	for lrow in left_rows:
		for rrow in right_rows:
			if _match_join_condition(lrow, rrow, condition, params):
				var merged: Dictionary = lrow.duplicate(true)
				for k in rrow.keys():
					if not merged.has(k):
						merged[k] = rrow[k]
				result.append(merged)
	return result


func _apply_left_join(left_rows: Array, right_rows: Array, condition: String, params: Array) -> Array:
	var result: Array = []
	for lrow in left_rows:
		var found := false
		for rrow in right_rows:
			if _match_join_condition(lrow, rrow, condition, params):
				var merged: Dictionary = lrow.duplicate(true)
				for k in rrow.keys():
					if not merged.has(k):
						merged[k] = rrow[k]
				result.append(merged)
				found = true
				break
		if not found:
			result.append(lrow.duplicate(true))
	return result


func _match_join_condition(left: Dictionary, right: Dictionary, condition: String, params: Array) -> bool:
	var conds := _parse_where_full(condition, params)
	return _match_conds_full_with_join(left, right, conds, params)


func _match_conds_full_with_join(left: Dictionary, right: Dictionary, conds: Array, params: Array) -> bool:
	for c in conds:
		var col_spec: String = c.get("col", "")
		var op: String = c.get("op", "=")
		var pidx: int = c.get("param", -1)
		var val: Variant = null
		var is_subquery: bool = c.get("subquery", false)
		
		if is_subquery:
			var subquery_sql: String = c.get("subquery_sql", "")
			var subquery_result := query(subquery_sql, params)
			var subquery_vals: Array = []
			for row in subquery_result:
				if row is Dictionary:
					subquery_vals.append(row)
			if col_spec.begins_with("t1."):
				val = left.get(col_spec.substr(4), null)
			elif col_spec.begins_with("t2."):
				val = right.get(col_spec.substr(4), null)
			else:
				val = null
		else:
			var lhs_row := left
			if col_spec.begins_with("t1."):
				lhs_row = left
				col_spec = col_spec.substr(4)
			elif col_spec.begins_with("t2."):
				lhs_row = right
				col_spec = col_spec.substr(4)
			
			if pidx >= 0 and pidx < params.size():
				val = params[pidx]
			
			if not _match_operator(lhs_row.get(col_spec, null), val, op):
				return false
	return true


func _parse_where_full(clause: String, params: Array) -> Array:
	var conds: Array = []
	var parts := clause.split(" AND ", false)
	for part in parts:
		var subparts := part.split(" OR ", false)
		var or_group: bool = subparts.size() > 1
		for sub in subparts:
			var cond := _parse_single_condition(sub.strip_edges(), params)
			if cond != null:
				cond["or_group"] = or_group
			conds.append(cond)
	return conds


func _parse_single_condition(clause: String, params: Array) -> Dictionary:
	clause = clause.strip_edges()
	
	# Check for IN clause
	var upper := clause.to_upper()
	if upper.begins_with("(") and upper.ends_with(")"):
		var in_content := clause.substr(1, clause.length() - 2).strip_edges()
		if in_content.length() > 0:
			if in_content.to_upper().begins_with("SELECT"):
				# Subquery
				var subquery_sql := "SELECT " + in_content.substr(6) + " FROM t"
				return {
					"col": "t",
					"op": "IN_SUBQUERY",
					"subquery_sql": subquery_sql
				}
			else:
				# Literal values
				var values := _parse_in_values(in_content, params)
				# Parse column IN (value1, value2)
				var col_end := clause.find(" IN(")
				if col_end >= 0:
					var col := clause.substr(0, col_end).strip_edges()
					return {
						"col": col,
						"op": "IN",
						"params": values
					}
	
	# Check for operators (>=, <=, >, <, !=, LIKE, =)
	var operators := ["IN(", " LIKE ", " like ", ">=", "<=", "!=", ">", "<", " = ", "="]
	var op_idx := -1
	var op_str := ""
	
	for i in range(operators.size() - 1, -1, -1):
		var op: String = operators[i]
		var idx := clause.to_upper().find(op)
		if idx >= 0:
			op_idx = idx
			op_str = op
			break
		
	if op_idx < 0:
			return {}
	
	var col := clause.substr(0, op_idx).strip_edges()
	var rhs := clause.substr(op_idx + op_str.length()).strip_edges()
	
	if col.to_upper().begins_with("NOT "):
		col = col.substr(4).strip_edges()
	
	var param_idx := -1
	var literal_val: Variant = null
	
	if rhs.begins_with("$"):
		var idx_str := rhs.substr(1)
		if idx_str.is_valid_int():
			var idx := idx_str.to_int() - 1
			if idx >= 0 and idx < params.size():
				param_idx = idx
				literal_val = params[idx]
		else:
			literal_val = _parse_literal(rhs)
	else:
		literal_val = _parse_literal(rhs)
		
	var result: Dictionary = {"col": col, "op": op_str.strip_edges(), "param": param_idx, "val": literal_val}
	if op_str.to_upper() == "IN(":
		result["op"] = "IN"
		result["params"] = _parse_in_values(rhs.substr(3, rhs.length() - 4), params)
	return result


func _parse_in_values(content: String, params: Array) -> Array:
	var values: Array = []
	var depth := 0
	var current := ""
	var in_quotes := false
	var quote_char := ""
	
	for i in range(content.length()):
		var c := content[i]
		
		if in_quotes:
			current += c
			if c == quote_char and (i == 0 or content[i-1] != "\\"):
				in_quotes = false
				quote_char = ""
		elif c == "'" or c == '"':
			in_quotes = true
			quote_char = c
			current += c
		elif c == "(":
			depth += 1
			current += c
		elif c == ")":
			depth -= 1
			current += c
		elif c == "," and depth == 0:
			var v := current.strip_edges()
			if v != "":
				values.append(_parse_scalar_value(v, params))
			current = ""
		else:
			current += c
		
	var v := current.strip_edges()
	if v != "":
		values.append(_parse_scalar_value(v, params))
	
	return values


func _parse_scalar_value(s: String, params: Array) -> Variant:
	s = s.strip_edges()
	if s.begins_with("$"):
		var idx_str := s.substr(1)
		if idx_str.is_valid_int():
			var idx := idx_str.to_int() - 1
			if idx >= 0 and idx < params.size():
				return params[idx]
	return _parse_literal(s)


func _parse_literal(s: String) -> Variant:
	s = s.strip_edges()
	if s.begins_with("'") and s.ends_with("'"):
		return s.substr(1, s.length() - 2)
	if s.begins_with('"') and s.ends_with('"'):
		return s.substr(1, s.length() - 2)
	if s.to_upper() == "NULL":
		return null
	if s.to_upper() == "TRUE":
		return true
	if s.to_upper() == "FALSE":
		return false
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	return s


func _match_conds_full(row: Dictionary, conds: Array, params: Array) -> bool:
	for c in conds:
		var col: String = c.get("col", "")
		var op: String = c.get("op", "=")
		var param_idx: int = c.get("param", -1)
		var val: Variant = c.get("val", null)
		var is_or_group: bool = c.get("or_group", false)
		
		if op == "IN_SUBQUERY":
			var subquery_sql: String = c.get("subquery_sql", "")
			var row_val = row.get(col, null)
			var subquery_result := query(subquery_sql, params)
			var found := false
			for r in subquery_result:
				if r is Dictionary and r.has(col) and r[col] == row_val:
					found = true
					break
			if not found:
				return false
		elif op == "IN":
			var row_val = row.get(col, null)
			var found := false
			for v in c.get("params", []):
				if v == row_val:
					found = true
					break
			if not found:
				return false
		else:
			var row_val = row.get(col, null)
			if op == " LIKE ":
				op = " LIKE"
			var test_val = val if param_idx < 0 else params[param_idx]
			if not _match_operator(row_val, test_val, op):
				return false
	return true


func _match_conds(row: Dictionary, conds: Array, params: Array) -> bool:
	for c in conds:
		var col: String = c["col"]
		var idx: int = c["param"]
		if idx < 0 or idx >= params.size():
			return false
		if row.get(col) != params[idx]:
			return false
	return true


func _match_operator(lhs: Variant, rhs: Variant, op: String) -> bool:
	if op == "=":
		return lhs == rhs
	if op == "!=":
		return lhs != rhs
		
	# Handle NULL comparisons
	if lhs == null:
		if op == "IS NULL":
			return true
		if op == "IS NOT NULL":
			return false
		# For other ops with NULL, return false
		return false
	if rhs == null:
		if op == "IS NULL":
			return false
		if op == "IS NOT NULL":
			return true
		
	# Comparison operators for non-NULL values
	if op == ">=":
		return lhs >= rhs
	if op == "<=":
		return lhs <= rhs
	if op == ">":
		return lhs > rhs
	if op == "<":
		return lhs < rhs
	if op == "LIKE":
		var text := lhs as String
		var pattern := rhs as String
		if text == null or pattern == null:
			return false
		return _match_like(text, pattern)
	return false


func _match_like(text: String, pattern: String) -> bool:
	if text == null or pattern == null:
		return false
	var regex_str := ""
	for i in range(pattern.length()):
		var c := pattern[i]
		if c == "%":
			regex_str += ".*"
		elif c == "_":
			regex_str += "."
		elif c == "\\" and i + 1 < pattern.length():
			var next := pattern[i + 1]
			if next == "%" or next == "_" or next == "\\":
				regex_str += "\\" + next
				i += 1
			else:
				regex_str += "\\" + next
				i += 1
		elif c >= "A" and c <= "Z":
			regex_str += "[" + c.to_lower() + c.to_upper() + "]"
		elif c >= "a" and c <= "z":
			regex_str += "[" + c.to_upper() + c.to_lower() + "]"
		else:
			regex_str += c

	if regex_str == "":
		regex_str = ".*"
	var reg_ex := RegEx.new()
	reg_ex.compile(regex_str)
	return reg_ex.search(text.to_lower()) != null
func _parse_order_by(sql: String, params: Array) -> Array:
	var result: Array = []
	
	sql = sql.strip_edges()
	
	while sql.length() > 0:
		var col: String = ""
		var dir: String = "ASC"
		
		# Extract column name
		var space_idx := sql.find(" ")
		if space_idx >= 0:
			col = sql.substr(0, space_idx).strip_edges()
			var after_col := sql.substr(space_idx + 1).strip_edges()
			
			# Check for ASC/DESC
			if after_col.to_upper().begins_with("ASC"):
				dir = "ASC"
				# Remove ASC and any following comma/space
				var after_asc := after_col.substr(3).strip_edges()
				if after_asc.begins_with(","):
					after_asc = after_asc.substr(1).strip_edges()
				elif after_asc.begins_with(" "):
					after_asc = after_asc.substr(1).strip_edges()
					sql = after_asc
				elif after_asc.length() == 0:
					sql = ""
			elif after_col.to_upper().begins_with("DESC"):
				dir = "DESC"
				var after_desc := after_col.substr(5).strip_edges()
				if after_desc.begins_with(","):
					after_desc = after_desc.substr(1).strip_edges()
				elif after_desc.begins_with(" "):
					after_desc = after_desc.substr(1).strip_edges()
					sql = after_desc
				elif after_desc.length() == 0:
					sql = ""
			else:
				sql = after_col
		
		else:
			col = sql.strip_edges()
			var after_col := ""
			
			if sql.begins_with(","):
				sql = sql.substr(1).strip_edges()
			
			if sql.to_upper().begins_with("ASC"):
				dir = "ASC"
				var after_asc := sql.substr(3).strip_edges()
				if after_asc.begins_with(","):
					after_asc = after_asc.substr(1).strip_edges()
					sql = after_asc
				elif after_asc.begins_with(" "):
					after_asc = after_asc.substr(1).strip_edges()
					sql = after_asc
				elif after_asc.length() == 0:
					sql = ""
					
			elif sql.to_upper().begins_with("DESC"):
				dir = "DESC"
				var after_desc := sql.substr(5).strip_edges()
				if after_desc.begins_with(","):
					after_desc = after_desc.substr(1).strip_edges()
				elif after_desc.begins_with(" "):
					after_desc = after_desc.substr(1).strip_edges()
					sql = after_desc
				elif after_desc.length() == 0:
					sql = ""
					
			else:
				sql = sql
			
		if col.length() > 0:
			result.append({"col": col, "dir": dir})
			if sql.begins_with(","):
				sql = sql.substr(1).strip_edges()
			elif sql.length() == 0:
				break
			else:
				break

	return result

func _apply_order_by(rows: Array, order_info: Array) -> Array:
	if order_info.is_empty():
		return rows
	
	rows.sort_custom(func(a, b):
		for o in order_info:
			var col: String = o["col"]
			var dir: String = o["dir"]
			var av: Variant = a.get(col, null)
			var bv: Variant = b.get(col, null)
			
			if av == bv:
				continue
			
			if dir == "ASC":
				if av == null:
					return true
				if bv == null:
					return false
				
				if av is Variant and bv is Variant:
					if av < bv:
						return true
					return false
				else:
					# String comparison
					if av < bv:
						return true
					return false
			else:
				if bv == null:
					return true
				if av == null:
					return false
				
				if av is Variant and bv is Variant:
					if av > bv:
						return true
					return false
				else:
					# String comparison
					if av > bv:
						return true
					return false
					
		return false
	)
	return rows

func _apply_group_by(rows: Array, group_cols: Array, params: Array) -> Array:
	if group_cols.is_empty():
		return rows
	
	var groups: Dictionary = {}
	for row in rows:
		var key_parts: Array = []
		for col in group_cols:
			key_parts.append(str(row.get(col, "")))
		var key := ",".join(key_parts)
		
		if not groups.has(key):
			groups[key] = []
		groups[key].append(row)
	
	var result: Array = []
	for key in groups.keys():
		var group_rows: Array = groups[key]
		var agg: Dictionary = group_rows[0].duplicate(true)
		result.append(agg)
	
	return result


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


func _parse_where(clause: String) -> Array:
	var conds: Array = []
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


# --- INSERT Parsing and Execution ---

func _exec_insert(sql: String, params: Array) -> int:
	var upper := sql.to_upper()
	var on_conflict_idx := upper.find(" ON CONFLICT")
	var has_on_conflict := on_conflict_idx >= 0
	
	var main_sql := sql
	var on_conflict_sql := ""
	if has_on_conflict:
		main_sql = sql.substr(0, on_conflict_idx)
		var after_conflict := sql.substr(on_conflict_idx).strip_edges().to_upper()
		if after_conflict.find(" DO NOTHING") >= 0:
			on_conflict_sql = "DO_NOTHING"
		elif after_conflict.find(" DO UPDATE") >= 0:
			on_conflict_sql = "DO_UPDATE"
		
	var into_idx := main_sql.find("INTO")
	if into_idx < 0:
		return -1
	
	var rest := main_sql.substr(into_idx + 4).strip_edges()
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
	
	if has_on_conflict and on_conflict_sql == "DO_NOTHING":
		var conflict_col := "id"
		for col in columns:
			if col.to_upper().find("ID") >= 0:
				conflict_col = col
				break
			
		var existing_values: Dictionary = {}
		for row in (_tables[table] as Array):
			if row.has(conflict_col):
				existing_values[row[conflict_col]] = true
				
		var new_value := ""
		for i in range(columns.size()):
			if i < params.size():
				if columns[i] == conflict_col:
					new_value = str(params[i])
					break
			
		if new_value != "" and existing_values.has(new_value):
			return 0
			
	var values_part := after_cols.substr(paren_close + 1)
	var values_idx := values_part.to_upper().find("VALUES")
	if values_idx < 0:
		return -1
	values_part = values_part.substr(values_idx + 6).strip_edges()
	if values_part.begins_with("(") and values_part.ends_with(")"):
		values_part = values_part.substr(1, values_part.length() - 2)
	
	var t: Array = _tables[table]
	var entry: Dictionary = {}
	for i in range(columns.size()):
		if i < params.size():
			entry[columns[i]] = params[i]
		elif i < values_part.length():
			# Parse inline values
			var value_end := values_part.find(",")
			if value_end >= 0:
				var value_str := values_part.substr(0, value_end).strip_edges()
				entry[columns[i]] = _parse_literal(value_str)
				values_part = values_part.substr(value_end + 1).strip_edges()
			else:
				entry[columns[i]] = _parse_literal(values_part.strip_edges())
				break
	t.append(entry)
	return 1


# --- UPDATE Parsing and Execution ---

func _exec_update(sql: String, params: Array) -> int:
	var upper := sql.to_upper()
	var set_idx := upper.find("SET")
	var where_idx := upper.find(" WHERE ")
	
	if set_idx < 0 or where_idx < 0 or set_idx > where_idx:
		return -1
	
	var table := sql.substr(0, set_idx).strip_edges()
	table = table.substr(6).strip_edges()
	
	var set_part := sql.substr(set_idx + 3, where_idx - set_idx - 3).strip_edges()
	var where_part := sql.substr(where_idx + 7).strip_edges()
	
	var set_pairs := _parse_set(set_part)
	
	var set_count := set_pairs.size()
	var where_conds := _parse_where(where_part)
	# Both SET values and WHERE conds store GLOBAL $N indices (1-based,
	# over the full params array). Slicing here shifted every WHERE index
	# and made parameterized UPDATEs match no rows.
	var where_params := params
	
	if not _tables.has(table):
		return 0
		
	var t: Array = _tables[table]
	var updated := 0
	
	for row in t:
		if _match_conds(row, where_conds, where_params):
			for pair in set_pairs:
				var col: String = pair[0]
				var set_idx_in_params: int = pair[1]
				if set_idx_in_params >= 0 and set_idx_in_params < params.size():
					row[col] = params[set_idx_in_params]
			updated += 1
	return updated


# --- DELETE Parsing and Execution ---

func _exec_delete(sql: String, params: Array) -> int:
	var from_idx := sql.find("FROM")
	if from_idx < 0:
		return -1
	var rest := sql.substr(from_idx + 4).strip_edges()
	
	var lower := rest.to_lower()
	var where_idx := lower.find(" where ")
	
	if where_idx < 0:
		var table := rest.strip_edges()
		if not _tables.has(table):
			return 0
		var n := (_tables[table] as Array).size()
		_tables.erase(table)
		return n
		
	var table := rest.substr(0, where_idx).strip_edges()
	var where_str := rest.substr(where_idx + 7).strip_edges()
		
	if not _tables.has(table):
		return 0
		
	var t: Array = _tables[table]
	var conds := _parse_where(where_str)
	var initial_size := t.size()
	_tables[table] = t.filter(func(row): return not _match_conds(row, conds, params))
	return initial_size - (_tables[table] as Array).size()
	

# --- Test/dev helpers ---

func seed(table: String, rows: Array) -> void:
	_tables[table] = rows.duplicate(true)
	
	
func table_names() -> Array:
	return _tables.keys()
	
	
func row_count(table: String) -> int:
	if not _tables.has(table):
		return 0
	return (_tables[table] as Array).size()


# --- Helper functions ---

func _is_alpha(c: int) -> bool:
	# Check if character code is alphabetic (A-Z or a-z)
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


func _split_csv(s: String) -> Array:
	var result: Array = []
	for part in s.split(","):
		result.append(part.strip_edges())
	return result


func _get_all_keys() -> Array:
	var all_keys: Array = []
	for table_name in _tables.keys():
		var rows: Array = _tables[table_name] as Array
		for row in rows:
			if row is Dictionary:
				for key in row.keys():
					if not all_keys.has(key):
						all_keys.append(key)
	return all_keys