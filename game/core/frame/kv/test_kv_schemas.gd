## Cross-schema validation guards for the kv tree schemas (frame
## primitive, co-located). Locks audit round 19: every _validate reads
## untrusted fields as Variant and REJECTS wrong types, instead of
## throwing from a typed local (var x: String = value["x"]).
##
## definition/memory/social have tree-wrapper tests but no schema test;
## this covers their validators (seed/state are covered by their own
## test_frame_*_schema.gd files).
extends SceneTree

const DefinitionSchema = preload("res://core/frame/kv/definition_schema.gd")
const MemorySchema = preload("res://core/frame/kv/memory_schema.gd")
const SocialSchema = preload("res://core/frame/kv/social_schema.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	var d := DefinitionSchema.new()
	_assert(d._validate({"def_type": "zone", "key": "k", "data": {}}), "definition: valid payload accepted")
	_assert(not d._validate({"def_type": 123, "key": "k", "data": {}}), "definition: wrong-typed def_type rejected (no throw)")
	_assert(not d._validate({"def_type": "zone", "key": 5, "data": {}}), "definition: wrong-typed key rejected")
	_assert(not d._validate({"def_type": "zone", "key": "k", "data": []}), "definition: wrong-typed data rejected")

	var m := MemorySchema.new()
	_assert(m._validate({"kind": "fact", "content": {}}), "memory: valid payload accepted")
	_assert(not m._validate({"kind": 7, "content": {}}), "memory: wrong-typed kind rejected (no throw)")
	_assert(not m._validate({"kind": "fact", "content": "x"}), "memory: wrong-typed content rejected")

	var s := SocialSchema.new()
	_assert(s._validate({"rel": "friend", "other_id": "p2"}), "social: valid payload accepted")
	_assert(not s._validate({"rel": 3, "other_id": "p2"}), "social: wrong-typed rel rejected (no throw)")
	_assert(not s._validate({"rel": "friend", "other_id": 9}), "social: wrong-typed other_id rejected")

	print("KV schema tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
