## SeedSchema test suite. Spec: labs/prd-seed-schema.md
extends SceneTree

const SeedSchemaScript = preload("res://data/roots/seed_schema.gd")

const SEED_TYPES := ["locked", "open", "frame"]
const VISIBILITY_SCOPES := ["world", "shard", "instance", "player"]

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_instantiation()
	_test_fields_default()
	_test_fields_settable()
	_test_validate_all_9_combos()
	_test_validate_missing_fields()
	_test_validate_invalid_seed_type()
	_test_validate_invalid_scope()
	_test_validate_path_not_string()
	_test_validate_parameters_not_dict()
	_test_canonical_determinism()
	_test_canonical_different_inputs()
	_test_canonical_empty_path()
	_test_canonical_special_chars()
	_test_canonical_length_prefix_format()
	_test_display_format()
	_test_display_empty_path()
	_test_display_zero_params()
	_test_display_all_9_combos()
	_test_tres_loads()
	_test_canonical_deep_path()
	_test_validate_empty_dict()
	_test_canonical_empty_parameters()
	_test_display_long_path()
	print("SeedSchema tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_instantiation() -> void:
	var schema := SeedSchemaScript.new()
	_assert(schema != null, "SeedSchema instantiation succeeds")
	_assert(schema is Resource, "SeedSchema is a Resource")


func _test_fields_default() -> void:
	var schema := SeedSchemaScript.new()
	_assert_eq(schema.get("seed_type"), "locked", "default seed_type is locked")
	_assert_eq(schema.get("visibility_scope"), "world", "default visibility_scope is world")
	_assert_eq(schema.get("version"), 1, "default version is 1")


func _test_fields_settable() -> void:
	var schema := SeedSchemaScript.new()
	schema.set("seed_type", "frame")
	schema.set("visibility_scope", "shard")
	_assert_eq(schema.get("seed_type"), "frame", "seed_type setter updates getter")
	_assert_eq(schema.get("visibility_scope"), "shard", "visibility_scope setter updates getter")


func _test_validate_all_9_combos() -> void:
	var schema := SeedSchemaScript.new()
	for seed_type in SEED_TYPES:
		for vis in VISIBILITY_SCOPES:
			var value := {"seed_type": seed_type, "visibility_scope": vis, "path": "/s", "parameters": {}}
			_assert(schema._validate(value) == true, "validates %s/%s" % [seed_type, vis])


func _test_validate_missing_fields() -> void:
	var schema := SeedSchemaScript.new()
	_assert(schema._validate({"visibility_scope": "world", "path": "/s", "parameters": {}}) == false, "missing seed_type")
	_assert(schema._validate({"seed_type": "locked", "path": "/s", "parameters": {}}) == false, "missing visibility_scope")
	_assert(schema._validate({"seed_type": "locked", "visibility_scope": "world", "parameters": {}}) == false, "missing path")
	_assert(schema._validate({"seed_type": "locked", "visibility_scope": "world", "path": "/s"}) == false, "missing parameters")


func _test_validate_invalid_seed_type() -> void:
	var schema := SeedSchemaScript.new()
	_assert(schema._validate({"seed_type": "bad", "visibility_scope": "world", "path": "/s", "parameters": {}}) == false, "invalid seed_type rejected")


func _test_validate_invalid_scope() -> void:
	var schema := SeedSchemaScript.new()
	_assert(schema._validate({"seed_type": "locked", "visibility_scope": "bad", "path": "/s", "parameters": {}}) == false, "invalid scope rejected")


func _test_validate_path_not_string() -> void:
	var schema := SeedSchemaScript.new()
	_assert(schema._validate({"seed_type": "locked", "visibility_scope": "world", "path": 123, "parameters": {}}) == false, "integer path rejected")


func _test_validate_parameters_not_dict() -> void:
	var schema := SeedSchemaScript.new()
	_assert(schema._validate({"seed_type": "locked", "visibility_scope": "world", "path": "/s", "parameters": "str"}) == false, "string parameters rejected")


func _test_canonical_determinism() -> void:
	var schema := SeedSchemaScript.new()
	var value := {"seed_type": "open", "visibility_scope": "shard", "path": "/z/1", "parameters": {"depth": 3}}
	_assert_eq(schema._to_canonical_bytes(value), schema._to_canonical_bytes(value), "same input produces identical bytes")


func _test_canonical_different_inputs() -> void:
	var schema := SeedSchemaScript.new()
	var base := {"seed_type": "locked", "visibility_scope": "world", "path": "/s", "parameters": {"c": 1}}
	var base_bytes := schema._to_canonical_bytes(base)
	var changed_type := base.duplicate(); changed_type["seed_type"] = "frame"
	_assert(base_bytes != schema._to_canonical_bytes(changed_type), "different seed_type produces different bytes")
	var changed_path := base.duplicate(); changed_path["path"] = "/other"
	_assert(base_bytes != schema._to_canonical_bytes(changed_path), "different path produces different bytes")


func _test_canonical_empty_path() -> void:
	var schema := SeedSchemaScript.new()
	var value := {"seed_type": "frame", "visibility_scope": "player", "path": "", "parameters": {"x": true}}
	var bytes := schema._to_canonical_bytes(value)
	_assert(bytes is PackedByteArray, "empty path produces PackedByteArray")
	_assert(bytes.size() > 0, "empty path produces non-empty bytes")


func _test_canonical_special_chars() -> void:
	var schema := SeedSchemaScript.new()
	var slash_bytes := schema._to_canonical_bytes({"seed_type": "locked", "visibility_scope": "world", "path": "/a/b/c", "parameters": {}})
	var bracket_bytes := schema._to_canonical_bytes({"seed_type": "locked", "visibility_scope": "world", "path": "a[b]c", "parameters": {}})
	_assert(slash_bytes != bracket_bytes, "slash and bracket paths produce different bytes")


func _test_canonical_length_prefix_format() -> void:
	var schema := SeedSchemaScript.new()
	var value := {"seed_type": "frame", "visibility_scope": "instance", "path": "/a/b/c", "parameters": {"d": 2}}
	var bytes := schema._to_canonical_bytes(value)
	var offset := 0
	_assert_eq(_read_u32_le(bytes, offset), 5, "seed_type length prefix is 5 (frame)")
	offset += 4 + 5
	_assert_eq(_read_u32_le(bytes, offset), 8, "visibility_scope length prefix is 8 (instance)")
	offset += 4 + 8
	_assert_eq(_read_u32_le(bytes, offset), 5, "path length prefix is 5 (/a/b/c)")
	offset += 4 + 5
	_assert_eq(_read_u32_le(bytes, offset), JSON.stringify({"d": 2}).length(), "parameters JSON length prefix matches")
	offset += 4 + JSON.stringify({"d": 2}).length()
	_assert_eq(offset, bytes.size(), "canonical encoding has no trailing bytes")


func _test_display_format() -> void:
	var schema := SeedSchemaScript.new()
	var display := schema._to_display({"seed_type": "locked", "visibility_scope": "world", "path": "/s1/z5", "parameters": {"d": 3, "b": "f", "a": true}})
	_assert_eq(display, "[locked+world] /s1/z5 (3 params)", "display includes type, scope, path, param count")


func _test_display_empty_path() -> void:
	var schema := SeedSchemaScript.new()
	var display := schema._to_display({"seed_type": "open", "visibility_scope": "shard", "path": "", "parameters": {}})
	_assert_eq(display, "[open+shard] (root) (0 params)", "empty path displays as root")


func _test_display_zero_params() -> void:
	var schema := SeedSchemaScript.new()
	var display := schema._to_display({"seed_type": "frame", "visibility_scope": "player", "path": "/z", "parameters": {}})
	_assert_eq(display, "[frame+player] /z (0 params)", "zero params displays as (0 params)")


func _test_display_all_9_combos() -> void:
	var schema := SeedSchemaScript.new()
	for st in SEED_TYPES:
		for vis in VISIBILITY_SCOPES:
			var d := schema._to_display({"seed_type": st, "visibility_scope": vis, "path": "/c", "parameters": {"v": 1}})
			_assert_eq(d, "[%s+%s] /c (1 params)" % [st, vis], "display formats %s/%s" % [st, vis])


func _test_tres_loads() -> void:
	var res := load("res://data/roots/world/seed.tres")
	_assert(res != null, "seed.tres loads")
	_assert_eq(res.get("seed_type"), "locked", "seed_type loaded from .tres")


func _test_canonical_deep_path() -> void:
	var schema := SeedSchemaScript.new()
	var v := {"seed_type": "locked", "visibility_scope": "world", "path": "/a/b/c/d/e/f/g/h", "parameters": {}}
	_assert(schema._validate(v) == true, "deep path is valid")
	_assert(schema._to_canonical_bytes(v).size() > 0, "deep path encodes")


func _test_validate_empty_dict() -> void:
	var schema := SeedSchemaScript.new()
	_assert(schema._validate({}) == false, "empty dict rejected")


func _test_canonical_empty_parameters() -> void:
	var schema := SeedSchemaScript.new()
	var v := {"seed_type": "open", "visibility_scope": "shard", "path": "/s", "parameters": {}}
	_assert(schema._validate(v) == true, "empty parameters are valid")
	_assert(schema._to_canonical_bytes(v).size() > 0, "empty parameters encode")


func _test_display_long_path() -> void:
	var schema := SeedSchemaScript.new()
	var lp := ""
	for i in range(250):
		lp += "/seg_%d" % i
	var d := schema._to_display({"seed_type": "locked", "visibility_scope": "world", "path": lp, "parameters": {}})
	_assert(d.find(lp) >= 0, "long path preserved in display")


func _read_u32_le(bytes: PackedByteArray, offset: int) -> int:
	return bytes[offset] + (bytes[offset + 1] << 8) + (bytes[offset + 2] << 16) + (bytes[offset + 3] << 24)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
	elif not condition:
		_failed += 1
		print("  [FAIL] %s" % label)
	else:
		_passed += 1
		print("  [PASS] %s" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
