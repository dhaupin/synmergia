## StateSchema test suite. Spec: labs/prd-state-schema.md
## Position values are quantized to 0.01m; behavior_state
## validates FSM enum (idle/move/attack/interact) and
## ai_tick_state must be int.
extends SceneTree

const StateSchemaScript = preload("res://core/frame/schemas/state_schema.gd")

const STATE_TYPES := ["position", "inventory", "health", "faction", "status", "quest", "social", "behavior_state", "other"]

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_instantiation()
	_test_fields_default()
	_test_fields_settable()
	_test_validate_all_types()
	_test_validate_missing_fields()
	_test_validate_invalid_type()
	_test_validate_entity_id_not_string()
	_test_validate_payload_not_dict()
	_test_validate_position()
	_test_validate_health()
	_test_validate_inventory()
	_test_validate_faction()
	_test_validate_status()
	_test_validate_quest()
	_test_validate_social()
	_test_validate_behavior_state()
	_test_validate_other()
	_test_canonical_determinism()
	_test_canonical_different_types()
	_test_canonical_different_payloads()
	_test_canonical_empty_entity_id()
	_test_canonical_nested_payload()
	_test_display_position()
	_test_display_health()
	_test_display_inventory()
	_test_display_all_types()
	_test_tres_loads()
	_test_validate_empty_dict()
	_test_canonical_empty_payload()
	_test_display_missing_optional_fields()
	_test_deep_nested_payload()
	_test_type_to_enum_consistency()
	print("StateSchema tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_instantiation() -> void:
	_assert(StateSchemaScript.new() != null, "StateSchema instantiation succeeds")
	_assert(StateSchemaScript.new() is Resource, "StateSchema is a Resource")


func _test_fields_default() -> void:
	var s := StateSchemaScript.new()
	_assert_eq(s.get("type"), "position", "default type is position")
	_assert_eq(s.get("version"), 1, "default version is 1")


func _test_fields_settable() -> void:
	var s := StateSchemaScript.new()
	s.set("type", "health")
	_assert_eq(s.get("type"), "health", "type setter updates getter")


func _test_validate_all_types() -> void:
	var s := StateSchemaScript.new()
	for t in STATE_TYPES:
		_assert(s._validate(_payload(t)) == true, "validates type: %s" % t)


func _test_validate_missing_fields() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"entity_id": "e", "payload": {}}) == false, "missing type rejected")
	_assert(s._validate({"type": "position", "payload": {}}) == false, "missing entity_id rejected")
	_assert(s._validate({"type": "position", "entity_id": "e"}) == false, "missing payload rejected")


func _test_validate_invalid_type() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "bad", "entity_id": "e", "payload": {}}) == false, "invalid type rejected")


func _test_validate_entity_id_not_string() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "position", "entity_id": 123, "payload": {}}) == false, "integer entity_id rejected")


func _test_validate_payload_not_dict() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "position", "entity_id": "e", "payload": "s"}) == false, "string payload rejected")


func _test_validate_position() -> void:
	var s := StateSchemaScript.new()
	# Int coordinates are accepted (converted to float 0.01m quantized).
	_assert(s._validate({"type": "position", "entity_id": "e", "payload": {"x": 1, "y": 0, "z": -5}}) == true, "valid int position accepted")
	# Float coordinates quantized to 0.01m are accepted.
	_assert(s._validate({"type": "position", "entity_id": "e", "payload": {"x": 1.0, "y": 0.0, "z": -5.0}}) == true, "valid quantized float position accepted")
	_assert(s._validate({"type": "position", "entity_id": "e", "payload": {"x": 1.0, "y": 0.0}}) == false, "position missing z rejected")
	_assert(s._validate({"type": "position", "entity_id": "e", "payload": {"x": "bad", "y": 0.0, "z": 1.0}}) == false, "position with string x rejected")
	# Non-quantized float should be rejected.
	_assert(s._validate({"type": "position", "entity_id": "e", "payload": {"x": 1.005, "y": 0.0, "z": 1.0}}) == false, "non-quantized float x rejected")


func _test_validate_health() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "health", "entity_id": "e", "payload": {"current": 50, "max": 100}}) == true, "valid health accepted")
	_assert(s._validate({"type": "health", "entity_id": "e", "payload": {"max": 100}}) == false, "health missing current rejected")


func _test_validate_inventory() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "inventory", "entity_id": "e", "payload": {"items": ["a"]}}) == true, "valid inventory accepted")
	_assert(s._validate({"type": "inventory", "entity_id": "e", "payload": {"items": {"a": 1}}}) == false, "inventory with dict items rejected")


func _test_validate_faction() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "faction", "entity_id": "e", "payload": {"faction_id": "al", "standing": 50.0}}) == true, "valid faction accepted")
	_assert(s._validate({"type": "faction", "entity_id": "e", "payload": {"faction_id": "al"}}) == false, "faction missing standing rejected")


func _test_validate_status() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "status", "entity_id": "e", "payload": {"effects": ["b"]}}) == true, "valid status accepted")
	_assert(s._validate({"type": "status", "entity_id": "e", "payload": {"effects": {"b": true}}}) == false, "status with dict effects rejected")


func _test_validate_quest() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "quest", "entity_id": "e", "payload": {"quest_id": "q1", "progress": 50}}) == true, "valid quest accepted")
	_assert(s._validate({"type": "quest", "entity_id": "e", "payload": {"quest_id": "q1", "progress": "half"}}) == false, "quest with string progress rejected")


func _test_validate_social() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "social", "entity_id": "e", "payload": {"relations": {"a": "f"}}}) == true, "valid social accepted")
	_assert(s._validate({"type": "social", "entity_id": "e", "payload": {"relations": ["a"]}}) == false, "social with array relations rejected")


func _test_validate_behavior_state() -> void:
	# Valid FSM states are now enforced: idle, move, attack, interact.
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "behavior_state", "entity_id": "e", "payload": {"current_state": "idle", "ai_tick_state": 3}}) == true, "valid behavior_state accepted")
	_assert(s._validate({"type": "behavior_state", "entity_id": "e", "payload": {"current_state": "idle"}}) == false, "behavior_state missing ai_tick_state rejected")
	# Invalid FSM state should be rejected.
	_assert(s._validate({"type": "behavior_state", "entity_id": "e", "payload": {"current_state": "patrol", "ai_tick_state": 3}}) == false, "invalid FSM state 'patrol' rejected")
	# ai_tick_state must be int.
	_assert(s._validate({"type": "behavior_state", "entity_id": "e", "payload": {"current_state": "move", "ai_tick_state": "3"}}) == false, "string ai_tick_state rejected")


func _test_validate_other() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({"type": "other", "entity_id": "e", "payload": {}}) == true, "other accepts empty payload")
	_assert(s._validate({"type": "other", "entity_id": "e", "payload": {"x": 1}}) == true, "other accepts any payload")


func _test_canonical_determinism() -> void:
	var s := StateSchemaScript.new()
	var v := {"type": "health", "entity_id": "p1", "payload": {"current": 50, "max": 100}}
	_assert_eq(s._to_canonical_bytes(v), s._to_canonical_bytes(v), "same input produces identical bytes")


func _test_canonical_different_types() -> void:
	var s := StateSchemaScript.new()
	var a := s._to_canonical_bytes({"type": "position", "entity_id": "e", "payload": {"x": 1, "y": 2, "z": 3}})
	var b := s._to_canonical_bytes({"type": "health", "entity_id": "e", "payload": {"current": 50, "max": 100}})
	_assert(a != b, "different type produces different bytes")


func _test_canonical_different_payloads() -> void:
	var s := StateSchemaScript.new()
	var a := s._to_canonical_bytes({"type": "health", "entity_id": "e", "payload": {"current": 50, "max": 100}})
	var b := s._to_canonical_bytes({"type": "health", "entity_id": "e", "payload": {"current": 51, "max": 100}})
	_assert(a != b, "different payload values produce different bytes")


func _test_canonical_empty_entity_id() -> void:
	var s := StateSchemaScript.new()
	var b := s._to_canonical_bytes({"type": "other", "entity_id": "", "payload": {}})
	_assert(b is PackedByteArray, "empty entity_id produces PackedByteArray")
	_assert(b.size() > 0, "empty entity_id produces non-empty bytes")


func _test_canonical_nested_payload() -> void:
	var s := StateSchemaScript.new()
	var b := s._to_canonical_bytes({"type": "social", "entity_id": "e", "payload": {"relations": {"a": {"b": {"c": 1}}}}})
	_assert(b.size() > 0, "nested payload encodes")


func _test_display_position() -> void:
	var s := StateSchemaScript.new()
	_assert_eq(s._to_display({"type": "position", "entity_id": "mob_99", "payload": {"x": 10.0, "y": 0.0, "z": -5.0}}), "[position] mob_99 @ (10.00, 0.00, -5.00)", "position display")


func _test_display_health() -> void:
	var s := StateSchemaScript.new()
	_assert_eq(s._to_display({"type": "health", "entity_id": "mob_99", "payload": {"current": 50, "max": 100}}), "[health] mob_99 (50/100)", "health display")


func _test_display_inventory() -> void:
	var s := StateSchemaScript.new()
	_assert_eq(s._to_display({"type": "inventory", "entity_id": "p1", "payload": {"items": ["sword", "potion", "key"]}}), "[inventory] p1 (3 items)", "inventory display")


func _test_display_all_types() -> void:
	var s := StateSchemaScript.new()
	for t in STATE_TYPES:
		var d := s._to_display(_payload(t))
		_assert(d.begins_with("["), "display for %s begins with bracket" % t)


func _test_tres_loads() -> void:
	var res := load("res://data/roots/world/state.tres")
	_assert(res != null, "state.tres loads")
	_assert_eq(res.get("type"), "position", "state.tres type loaded")


func _test_validate_empty_dict() -> void:
	var s := StateSchemaScript.new()
	_assert(s._validate({}) == false, "empty dict rejected")


func _test_canonical_empty_payload() -> void:
	var s := StateSchemaScript.new()
	_assert(s._to_canonical_bytes({"type": "other", "entity_id": "e", "payload": {}}).size() > 0, "empty payload encodes")


func _test_display_missing_optional_fields() -> void:
	var s := StateSchemaScript.new()
	var d := s._to_display({"type": "other", "entity_id": "", "payload": {}})
	_assert(d.find("[other]") >= 0, "display with empty entity_id does not crash")


func _test_deep_nested_payload() -> void:
	var s := StateSchemaScript.new()
	var v := {"type": "social", "entity_id": "e", "payload": {"relations": {"a": {"b": {"c": {"d": 1}}}}}}
	_assert(s._validate(v) == true, "deeply nested payload validates")
	_assert(s._to_canonical_bytes(v).size() > 0, "deeply nested payload encodes")


func _test_type_to_enum_consistency() -> void:
	var s := StateSchemaScript.new()
	for t in STATE_TYPES:
		_assert(s._validate(_payload(t)) == true, "type %s passes _validate" % t)
		_assert(s._to_display(_payload(t)).find("[%s]" % t) >= 0, "type %s produces display with type prefix" % t)


func _payload(t: String) -> Dictionary:
	match t:
		"position": return {"type": "position", "entity_id": "e1", "payload": {"x": 1.0, "y": 2.0, "z": 3.0}}
		"inventory": return {"type": "inventory", "entity_id": "e1", "payload": {"items": ["a", "b"]}}
		"health": return {"type": "health", "entity_id": "e1", "payload": {"current": 50, "max": 100}}
		"faction": return {"type": "faction", "entity_id": "e1", "payload": {"faction_id": "all", "standing": 50.0}}
		"status": return {"type": "status", "entity_id": "e1", "payload": {"effects": ["buff"]}}
		"quest": return {"type": "quest", "entity_id": "e1", "payload": {"quest_id": "q1", "progress": 50}}
		"social": return {"type": "social", "entity_id": "e1", "payload": {"relations": {"a": "f"}}}
		"behavior_state": return {"type": "behavior_state", "entity_id": "e1", "payload": {"current_state": "idle", "ai_tick_state": 0}}
		"other": return {"type": "other", "entity_id": "e1", "payload": {"x": 1}}
	return {"type": "other", "entity_id": "e1", "payload": {}}


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
