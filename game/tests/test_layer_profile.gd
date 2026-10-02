## Round-10 guard: the LayerProfile .tres must match the audited
## de-facto bit map (2026-10-02). A data edit that renumbers a bit
## silent collision-behavior change. Bits 4+ are reserved; the legacy
## broad masks ride as explicit group "value" overrides. Also pins the
## static fallback and the named-bit conveniences.
extends SceneTree

const LayerProfileScript = preload("res://core/schemas/layer_profile.gd")

var _checks := 0
var _fails := 0


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true

	# The .tres loads through the schema (full game data path).
	var tres := load("res://data/physics_layers/physics_layers_main.tres")
	ok = _check("physics_layers_main.tres loads", tres != null) and ok
	ok = _check("tres is a LayerProfile", tres is LayerProfileScript) and ok

	if tres != null:
		# THE AUDIT LOCK: these values are what the shipped code uses.
		ok = _check("data: entity bit == 1", tres.bit("entity") == 1) and ok
		ok = _check("data: solid bit == 2", tres.bit("solid") == 2) and ok
		ok = _check("data: ground bit == 4", tres.bit("ground") == 4) and ok
		ok = _check("data: group world == entity|solid|ground (7)", tres.mask("world") == 7) and ok
		ok = _check("data: group entity_solid == 3", tres.mask("entity_solid") == 3) and ok
		ok = _check("data: group solid_ground == 6", tres.mask("solid_ground") == 6) and ok
		ok = _check("data: group all_solid == 63 (legacy value)", tres.mask("all_solid") == 63) and ok
		ok = _check("data: group geometry_no_entity == 126 (legacy)", tres.mask("geometry_no_entity") == 126) and ok
		ok = _check("data: group everything == 0xFFFFFFFF", tres.mask("everything") == 4294967295) and ok
		ok = _check("data: audit_locked stays true", tres.audit_locked) and ok
		ok = _check("data: unknown layer name -> 0 (not garbage)", tres.bit("does_not_exist") == 0) and ok
		ok = _check("data: unknown group -> 0", tres.mask("does_not_exist") == 0) and ok

	# Static fallback (no autoloads in --script mode): identical values.
	var fb: Resource = LayerProfileScript._default_profile()
	ok = _check("fallback: entity 1 / solid 2 / ground 4", \
		fb.bit("entity") == 1 and fb.bit("solid") == 2 and fb.bit("ground") == 4) and ok
	ok = _check("fallback: world 7 / all_solid 63 / everything 0xFFFFFFFF", \
		fb.mask("world") == 7 and fb.mask("all_solid") == 63 and fb.mask("everything") == 4294967295) and ok

	# Static conveniences resolve (DataService absent here -> fallback).
	ok = _check("static: Layers.layer_bit('entity') == 1", LayerProfileScript.layer_bit("entity") == 1) and ok
	ok = _check("static: Layers.group_mask('world') == 7", LayerProfileScript.group_mask("world") == 7) and ok

	print("--- RESULTS: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)
