## TestSeedSchema
##
## Tests for SeedSchema Resource (labs/prd-seed-schema.md)
## Covers US-001 through US-005 + edge cases

extends SceneTree

var schema: Resource
var ok: bool = true

func _init() -> void:
	_load_schema()
	_run_tests()
	quit(0 if ok else 1)

func _load_schema() -> void:
	var script = load("res://core/frame/schemas/seed_schema.gd")
	schema = script.new()

func _run_tests() -> void:
	# US-001: SeedSchema class with fields
	_test_schema_exists()
	_test_fields()

	# US-002: _to_canonical_bytes
	_test_canonical_bytes_basic()
	_test_canonical_bytes_deterministic()
	_test_canonical_bytes_different_inputs()
	_test_canonical_bytes_empty_path()
	_test_canonical_bytes_special_chars()

	# US-003: _validate
	_test_validate_valid()
	_test_validate_missing_fields()
	_test_validate_invalid_seed_type()
	_test_validate_invalid_scope()
	_test_validate_invalid_path_type()
	_test_validate_invalid_params_type()

	# US-004: _to_display
	_test_display_basic()
	_test_display_empty_path()
	_test_display_zero_params()

	# US-005: Sample .tres
	_test_sample_tres_loads()

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: %s" % msg)
		ok = false
	else:
		print("PASS: %s" % msg)

func _test_schema_exists() -> void:
	_assert(schema != null, "SeedSchema loads")
	_assert(schema is Resource, "SeedSchema extends Resource")

func _test_fields() -> void:
	_assert(schema.has_method("_to_canonical_bytes"), "has _to_canonical_bytes")
	_assert(schema.has_method("_validate"), "has _validate")
	_assert(schema.has_method("_to_display"), "has _to_display")
	_assert(schema.get("seed_type") == "locked", "default seed_type")
	_assert(schema.get("visibility_scope") == "world", "default visibility_scope")
	_assert(schema.get("version") == 1, "default version")

func _test_canonical_bytes_basic() -> void:
	var value := {
		"seed_type": "locked",
		"visibility_scope": "world",
		"path": "/shard_1/zone_5",
		"parameters": {"depth": 3, "biome": "forest"}
	}
	var bytes = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(bytes.size() > 0, "canonical_bytes non-empty")

func _test_canonical_bytes_deterministic() -> void:
	var value := {
		"seed_type": "open",
		"visibility_scope": "shard",
		"path": "/zone_1",
		"parameters": {"a": 1}
	}
	var b1 = schema._to_canonical_bytes(value) as PackedByteArray
	var b2 = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(b1 == b2, "canonical_bytes deterministic")

func _test_canonical_bytes_different_inputs() -> void:
	var v1 := {"seed_type": "locked", "visibility_scope": "world", "path": "/a", "parameters": {}}
	var v2 := {"seed_type": "open", "visibility_scope": "world", "path": "/a", "parameters": {}}
	var b1 = schema._to_canonical_bytes(v1) as PackedByteArray
	var b2 = schema._to_canonical_bytes(v2) as PackedByteArray
	_assert(b1 != b2, "different seed_type -> different bytes")

	v2 = {"seed_type": "locked", "visibility_scope": "shard", "path": "/a", "parameters": {}}
	b2 = schema._to_canonical_bytes(v2)
	_assert(b1 != b2, "different scope -> different bytes")

	v2 = {"seed_type": "locked", "visibility_scope": "world", "path": "/b", "parameters": {}}
	b2 = schema._to_canonical_bytes(v2)
	_assert(b1 != b2, "different path -> different bytes")

	v2 = {"seed_type": "locked", "visibility_scope": "world", "path": "/a", "parameters": {"x": 1}}
	b2 = schema._to_canonical_bytes(v2)
	_assert(b1 != b2, "different params -> different bytes")

func _test_canonical_bytes_empty_path() -> void:
	var value := {"seed_type": "frame", "visibility_scope": "player", "path": "", "parameters": {}}
	var bytes = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(bytes.size() > 0, "empty path encodes")

func _test_canonical_bytes_special_chars() -> void:
	var value := {"seed_type": "locked", "visibility_scope": "world", "path": "/zone/\u7279\u6B8A\u5B57/\U0001F332", "parameters": {"key": "value/with/slashes"}}
	var bytes = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(bytes.size() > 0, "special chars encode")
	var bytes2 = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(bytes == bytes2, "special chars deterministic")

func _test_validate_valid() -> void:
	var value := {"seed_type": "locked", "visibility_scope": "world", "path": "/a/b", "parameters": {"x": 1}}
	_assert(schema._validate(value) == true, "valid input passes")

	value = {"seed_type": "open", "visibility_scope": "shard", "path": "", "parameters": {}}
	_assert(schema._validate(value) == true, "valid empty path passes")

	value = {"seed_type": "frame", "visibility_scope": "player", "path": "/x", "parameters": {"nested": {"a": 1}}}
	_assert(schema._validate(value) == true, "valid nested params passes")

func _test_validate_missing_fields() -> void:
	var value := {"visibility_scope": "world", "path": "/a", "parameters": {}}
	_assert(schema._validate(value) == false, "missing seed_type fails")

	value = {"seed_type": "locked", "path": "/a", "parameters": {}}
	_assert(schema._validate(value) == false, "missing scope fails")

	value = {"seed_type": "locked", "visibility_scope": "world", "parameters": {}}
	_assert(schema._validate(value) == false, "missing path fails")

	value = {"seed_type": "locked", "visibility_scope": "world", "path": "/a"}
	_assert(schema._validate(value) == false, "missing parameters fails")

	value = {}
	_assert(schema._validate(value) == false, "empty dict fails")

func _test_validate_invalid_seed_type() -> void:
	var value := {"seed_type": "invalid", "visibility_scope": "world", "path": "/a", "parameters": {}}
	_assert(schema._validate(value) == false, "invalid seed_type fails")

	value = {"seed_type": "LOCKED", "visibility_scope": "world", "path": "/a", "parameters": {}}
	_assert(schema._validate(value) == false, "case-sensitive seed_type fails")

func _test_validate_invalid_scope() -> void:
	var value := {"seed_type": "locked", "visibility_scope": "invalid", "path": "/a", "parameters": {}}
	_assert(schema._validate(value) == false, "invalid scope fails")

	value = {"seed_type": "locked", "visibility_scope": "WORLD", "path": "/a", "parameters": {}}
	_assert(schema._validate(value) == false, "case-sensitive scope fails")

func _test_validate_invalid_path_type() -> void:
	var value := {"seed_type": "locked", "visibility_scope": "world", "path": 123, "parameters": {}}
	_assert(schema._validate(value) == false, "non-string path fails")

	value = {"seed_type": "locked", "visibility_scope": "world", "path": [], "parameters": {}}
	_assert(schema._validate(value) == false, "array path fails")

func _test_validate_invalid_params_type() -> void:
	var value := {"seed_type": "locked", "visibility_scope": "world", "path": "/a", "parameters": "not a dict"}
	_assert(schema._validate(value) == false, "string params fails")

	value = {"seed_type": "locked", "visibility_scope": "world", "path": "/a", "parameters": []}
	_assert(schema._validate(value) == false, "array params fails")

	value = {"seed_type": "locked", "visibility_scope": "world", "path": "/a", "parameters": 42}
	_assert(schema._validate(value) == false, "int params fails")

func _test_display_basic() -> void:
	var value := {"seed_type": "locked", "visibility_scope": "world", "path": "/shard_1/zone_5", "parameters": {"a": 1, "b": 2, "c": 3}}
	var display = schema._to_display(value) as String
	_assert(display == "[locked+world] /shard_1/zone_5 (3 params)", "basic display: %s" % display)

func _test_display_empty_path() -> void:
	var value := {"seed_type": "open", "visibility_scope": "shard", "path": "", "parameters": {}}
	var display = schema._to_display(value) as String
	_assert(display == "[open+shard] (root) (0 params)", "empty path display: %s" % display)

func _test_display_zero_params() -> void:
	var value := {"seed_type": "frame", "visibility_scope": "player", "path": "/zone", "parameters": {}}
	var display = schema._to_display(value) as String
	_assert(display == "[frame+player] /zone (0 params)", "zero params display: %s" % display)

func _test_sample_tres_loads() -> void:
	var res = load("res://data/roots/world/seed.tres")
	_assert(res != null, "seed.tres loads")
	_assert(res is Resource, "seed.tres is Resource")
	_assert(res.get_script() != null, "seed.tres has script")
