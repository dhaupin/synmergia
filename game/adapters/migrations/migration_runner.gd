## MigrationRunner - Versioned SQL migration runner for the adapter layer.
##
## A plain utility (RefCounted, not Node) so it can be instantiated via
## load().new() without a scene tree. Called once at boot by
## BackendFactory after the persistence store is registered.
##
## Each V*.sql file under res://adapters/migrations/ is applied in lexical
## order. Per-migration statements run inside a single transaction; a failure
## rolls back that migration only and aborts (stale schema is worse than a
## refused boot). Idempotent: skips versions already recorded in
## schema_migrations.
##
## Env:
##   MIGRATIONS_SKIP=1   skip migrations entirely (dev override)
##
## See: labs/prd-db.md sec.9
## ============================================================================
extends RefCounted

const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")


const MIGRATIONS_DIR := "res://adapters/migrations"
const METADATA_TABLE := "schema_migrations"


func run(store: PersistenceStore, log: Object = null) -> int:
	if OS.has_environment("MIGRATIONS_SKIP"):
		_log(log, "MigrationRunner: MIGRATIONS_SKIP set, skipping migrations")
		return 0

	if store == null:
		push_error("MigrationRunner: no persistence store resolved")
		return -1
	if not store.healthy():
		push_error("MigrationRunner: persistence store not healthy, cannot run migrations")
		return -1

	# Bootstrap the metadata table if absent.
	var rc := store.execute_batch([
		"CREATE TABLE IF NOT EXISTS %s (version VARCHAR(128) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum VARCHAR(64))" % METADATA_TABLE,
	])
	if rc != 0:
		push_error("MigrationRunner: failed to create %s" % METADATA_TABLE)
		return -1

	var files := _scan_migrations()
	if files.is_empty():
		_log(log, "MigrationRunner: no migrations found")
		return 0

	var applied := _load_applied(store)
	var run := 0

	for path in files:
		var version := _version_from_filename(path)
		if applied.has(version):
			_log(log, "MigrationRunner: %s already applied, skipping" % version)
			continue

		var sql := _read_file(path)
		if sql.is_empty():
			push_error("MigrationRunner: %s unreadable" % path)
			return -1

		var tx := store.begin()
		if tx < 0:
			push_error("MigrationRunner: begin failed for %s" % version)
			return -1

		var ok := true
		for stmt in _split_statements(sql):
			var s: String = stmt.strip_edges()
			if s == "":
				continue
			if store.execute(s, []) < 0:
				push_error("MigrationRunner: %s statement failed: %s" % [version, s])
				ok = false
				break

		if ok:
			store.execute(
				"INSERT INTO %s (version, checksum) VALUES ($1, $2) ON CONFLICT DO NOTHING" % METADATA_TABLE,
				[version, _checksum(sql)]
			)
			store.commit(tx)
			_log(log, "MigrationRunner: applied %s" % version)
			run += 1
		else:
			store.rollback(tx)
			return -1

	_log(log, "MigrationRunner: %d migration(s) applied" % run)
	return 0


func _scan_migrations() -> Array:
	var files: Array = []
	var dir := DirAccess.open(MIGRATIONS_DIR)
	if dir == null:
		return files
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("V") and name.ends_with(".sql"):
			files.append(MIGRATIONS_DIR.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


func _version_from_filename(path: String) -> String:
	# V20260907_001__init_accounts.sql -> 20260907_001
	var core := path.get_file().trim_suffix(".sql").replacen("__", "_")
	return core.substr(1)  # strip leading "V"


func _load_applied(store: PersistenceStore) -> Dictionary:
	var rows := store.query("SELECT version FROM %s" % METADATA_TABLE, [])
	var applied: Dictionary = {}
	for row in rows:
		applied[row.get("version", "")] = true
	return applied


func _split_statements(sql: String) -> Array:
	# Strip -- line comments first (respecting single-quoted strings),
	# then split on semicolons NOT inside strings. Without the comment
	# strip, migration headers ("-- First migration...") were handed to
	# execute() as statements and failed the run.
	var stripped := _strip_sql_comments(sql)
	var out: Array = []
	var buf: String = ""
	var in_str := false
	var i := 0
	while i < stripped.length():
		var ch := stripped[i]
		if ch == "'":
			in_str = not in_str
		if ch == ";" and not in_str:
			out.append(buf)
			buf = ""
		else:
			buf += ch
		i += 1
	if buf.strip_edges() != "":
		out.append(buf)
	return out


## Removes -- line comments outside of string literals. /* */ block
## comments are rare in these migrations but handled too.
func _strip_sql_comments(sql: String) -> String:
	var out := ""
	var in_str := false
	var in_line := false
	var in_block := false
	var i := 0
	while i < sql.length():
		var ch := sql[i]
		var nxt := sql[i + 1] if i + 1 < sql.length() else ""
		if in_line:
			if ch == "\n":
				in_line = false
				out += ch
			i += 1
			continue
		if in_block:
			if ch == "*" and nxt == "/":
				in_block = false
				i += 2
				continue
			i += 1
			continue
		if not in_str and ch == "-" and nxt == "-":
			in_line = true
			i += 2
			continue
		if not in_str and ch == "/" and nxt == "*":
			in_block = true
			i += 2
			continue
		if ch == "'":
			in_str = not in_str
		out += ch
		i += 1
	return out


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _checksum(text: String) -> String:
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _log(log: Object, msg: String) -> void:
	if log != null and log.has_method("info"):
		log.info(msg)
	else:
		# GameLog autoload is not resolvable when load()ed from --script mode.
		print("[INFO] %s" % msg)
