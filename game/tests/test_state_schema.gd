## TestStateSchema
##
## Tests for StateSchema Resource (labs/prd-state-schema.md)
## Covers US-001 through US-005 + edge cases

extends SceneTree

var schema: Resource
var ok: bool = true

func _init() -> void:
	_load_schema()
	_run_tests()
	quit(0 if ok else 1)

func _load_schema() -> void:
	var script = load("res://core/frame/schemas/state_schema.gd")
	schema = script.new()

func _run_tests() -> void:
	# US-001: StateSchema class with field
	_test_schema_exists()
	_test_fields()

	# US-002: _to_canonical_bytes
	_test_canonical_bytes_basic()
	_test_canonical_bytes_deterministic()
	_test_canonical_bytes_different_inputs()
	_test_canonical_bytes_empty_payload()

	# US-003: _validate
	_test_validate_valid()
	_test_validate_missing_fields()
	_test_validate_invalid_type()
	_test_validate_invalid_entity_id()
	_test_validate_invalid_payload()
	_test_validate_position_payload()
	_test_validate_health_payload()
	_test_validate_inventory_payload()

	# US-004: _to_display
	_test_display_position()
	_test_display_health()
	_test_display_inventory()
	_test_display_other_types()

	# US-005: Sample .tres
	_test_sample_tres_loads()

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: %s" % msg)
		ok = false
	else:
		print("PASS: %s" % msg)

func _test_schema_exists() -> void:
	_assert(schema != null, "StateSchema loads")
	_assert(schema is Resource, "StateSchema extends Resource")

func _test_fields() -> void:
	_assert(schema.has_method("_to_canonical_bytes"), "has _to_canonical_bytes")
	_assert(schema.has_method("_validate"), "has _validate")
	_assert(schema.has_method("_to_display"), "has _to_display")
	_assert(schema.get("type") == "position", "default type")
	_assert(schema.get("version") == 1, "default version")

func _test_canonical_bytes_basic() -> void:
	var value := {
		"type": "position",
		"entity_id": "player_42",
		"payload": {"x": 10.0, "y": 0.0, "z": -5.0}
	}
	var bytes = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(bytes.size() > 0, "canonical_bytes non-empty")

func _test_canonical_bytes_deterministic() -> void:
	var value := {
		"type": "health",
		"entity_id": "mob_99",
		"payload": {"current": 50, "max": 100}
	}
	var b1 = schema._to_canonical_bytes(value) as PackedByteArray
	var b2 = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(b1 == b2, "canonical_bytes deterministic")

func _test_canonical_bytes_different_inputs() -> void:
	var v1 := {"type": "position", "entity_id": "p1", "payload": {"x": 1.0, "y": 2.0, "z": 3.0}}
	var v2 := {"type": "inventory", "entity_id": "p1", "payload": {"x": 1.0, "y": 2.0, "z": 3.0}}
	var b1 = schema._to_canonical_bytes(v1) as PackedByteArray
	var b2 = schema._to_canonical_bytes(v2) as PackedByteArray
	_assert(b1 != b2, "different type -> different bytes")

	v2 = {"type": "position", "entity_id": "p2", "payload": {"x": 1.0, "y": 2.0, "z": 3.0}}
	b2 = schema._to_canonical_bytes(v2)
	_assert(b1 != b2, "different entity_id -> different bytes")

	v2 = {"type": "position", "entity_id": "p1", "payload": {"x": 9.0, "y": 2.0, "z": 3.0}}
	b2 = schema._to_canonical_bytes(v2)
	_assert(b1 != b2, "different payload -> different bytes")

func _test_canonical_bytes_empty_payload() -> void:
	var value := {"type": "other", "entity_id": "e1", "payload": {}}
	var bytes = schema._to_canonical_bytes(value) as PackedByteArray
	_assert(bytes.size() > 0, "empty payload encodes")

func _test_validate_valid() -> void:
	var value := {"type": "position", "entity_id": "player_42", "payload": {"x": 10.0, "y": 0.0, "z": -5.0}}
	_assert(schema._validate(value) == true, "valid position passes")

	value = {"type": "health", "entity_id": "mob_99", "payload": {"current": 50, "max": 100}}
	_assert(schema._validate(value) == true, "valid health passes")

	value = {"type": "inventory", "entity_id": "p1", "payload": {"items": ["sword", "shield"]}}
	_assert(schema._validate(value) == true, "valid inventory passes")

	value = {"type": "other", "entity_id": "e1", "payload": {"anything": true}}
	_assert(schema._validate(value) == true, "valid other passes")

func _test_validate_missing_fields() -> void:
	var value := {"entity_id": "p1", "payload": {}}
	_assert(schema._validate(value) == false, "missing type fails")

	value = {"type": "position", "payload": {}}
	_assert(schema._validate(value) == false, "missing entity_id fails")

	value = {"type": "position", "entity_id": "p1"}
	_assert(schema._validate(value) == false, "missing payload fails")

	value = {}
	_assert(schema._validate(value) == false, "empty dict fails")

func _test_validate_invalid_type() -> void:
	var value := {"type": "invalid", "entity_id": "p1", "payload": {}}
	_assert(schema._validate(value) == false, "invalid type fails")

	value = {"type": "POSITION", "entity_id": "p1", "payload": {}}
	_assert(schema._validate(value) == false, "case-sensitive type fails")

func _test_validate_invalid_entity_id() -> void:
	var value := {"type": "position", "entity_id": 42, "payload": {"x": 1.0, "y": 2.0, "z": 3.0}}
	_assert(schema._validate(value) == false, "non-string entity_id fails")

	value = {"type": "position", "entity_id": [], "payload": {"x": 1.0, "y": 2.0, "z": 3.0}}
	_assert(schema._validate(value) == false, "array entity_id fails")

func _test_validate_invalid_payload() -> void:
	var value := {"type": "position", "entity_id": "p1", "payload": "not a dict"}
	_assert(schema._validate(value) == false, "non-dict payload fails")

	value = {"type": "position", "entity_id": "p1", "payload": []}
	_assert(schema._validate(value) == false, "array payload fails")

func _test_validate_position_payload() -> void:
	var value := {"type": "position", "entity_id": "p1", "payload": {"x": 1.0, "y": 2.0}}
	_assert(schema._validate(value) == false, "position missing z fails")

	value = {"type": "position", "entity_id": "p1", "payload": {"x": "a", "y": 2.0, "z": 3.0}}
	_assert(schema._validate(value) == false, "position non-float x fails")

	value = {"type": "position", "entity_id": "p1", "payload": {"x": 1, "y": 2, "z": 3}}
	_assert(schema._validate(value) == true, "position int coords pass")

func _test_validate_health_payload() -> void:
	var value := {"type": "health", "entity_id": "p1", "payload": {"current": 50}}
	_assert(schema._validate(value) == false, "health missing max fails")

	value = {"type": "health", "entity_id": "p1", "payload": {"current": "a", "max": 100}}
	_assert(schema._validate(value) == false, "health non-int current fails")

	value = {"type": "health", "entity_id": "p1", "payload": {"current": 50, "max": 100}}
	_assert(schema._validate(value) == true, "valid health passes")

func _test_validate_inventory_payload() -> void:
	var value := {"type": "inventory", "entity_id": "p1", "payload": {}}
	_assert(schema._validate(value) == false, "inventory missing items fails")

	value = {"type": "inventory", "entity_id": "p1", "payload": {"items": "sword"}}
	_assert(schema._validate(value) == false, "inventory non-array items fails")

	value = {"type": "inventory", "entity_id": "p1", "payload": {"items": ["sword", "shield"]}}
	_assert(schema._validate(value) == true, "valid inventory passes")

func _test_display_position() -> void:
	var value := {"type": "position", "entity_id": "player_42", "payload": {"x": 10.0, "y": 0.0, "z": -5.0}}
	var display = schema._to_display(value) as String
	_assert(display == "[position] player_42 @ (10.00, 0.00, -5.00)", "position display: %s" % display)

func _test_display_health() -> void:
	var value := {"type": "health", "entity_id": "mob_99", "payload": {"current": 50, "max": 100}}
	var display = schema._to_display(value) as String
	_assert(display == "[health] mob_99 (50/100)", "health display: %s" % display)

func _test_display_inventory() -> void:
	var value := {"type": "inventory", "entity_id": "p1", "payload": {"items": ["sword", "shield", "potion"]}}
	var display = schema._to_display(value) as String
	_assert(display == "[inventory] p1 (3 items)", "inventory display: %s" % display)

func _test_display_other_types() -> void:
	var value := {"type": "faction", "entity_id": "p1", "payload": {"faction_id": "guardians", "standing": 75.5}}
	var display = schema._to_display(value) as String
	_assert(display == "[faction] p1 -> guardians (75.50)", "faction display: %s" % display)

	value = {"type": "status", "entity_id": "p1", "payload": {"effects": ["poison", "stun"]}}
	display = schema._to_display(value)
	_assert(display == "[status] p1 (2 effects)", "status display: %s" % display)

	value = {"type": "other", "entity_id": "e1", "payload": {}}
	display = schema._to_display(value)
	_assert(display == "[other] e1", "other display: %s" % display)

func _test_sample_tres_loads() -> void:
	var res = load("res://data/roots/world/state.tres")
	_assert(res != null, "state.tres loads")
	_assert(res is Resource, "state.tres is Resource")
	_assert(res.get_script() != null, "state.tres has script")
