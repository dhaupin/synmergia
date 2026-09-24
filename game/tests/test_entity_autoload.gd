extends SceneTree

# Regression test: the Entity autoload was removed (commit prior to this).
# Before the removal, Entity was BOTH an autoload (singleton Node3D) AND
# the class_name of the same script. The autoload shadowed the class_name,
# so Entity.new() failed with "Invalid call. Nonexistent function 'new'
# in base 'GDScript'."
#
# After the removal, the class_name Entity resolves to the script and
# Entity.new() works again.
#
# This test is self-contained: it does NOT rely on autoloads (since
# --script mode does not pre-load them). It only uses load() and the
# global class registry.
#
# Run with:
#   godot --headless --path . --script res://tests/test_entity_autoload.gd

var _passed: int = 0
var _failed: int = 0


func _ok(label: String) -> void:
	_passed += 1
	print("  PASS: ", label)


func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	printerr("  FAIL: ", label, " ", detail)


func _init() -> void:
	# Defer past --script autoload setup: entity.gd references the EventHub
	# autoload at compile time, and load()ing it inside _init (before
	# autoloads exist) yields a half-compiled script whose instances bind
	# nothing -- the exact "no script bound" symptom this test guards
	# against, but from boot ordering instead of an autoload shadow. Same
	# de-flake pattern as test_aggro_system.gd / test_hit_table.gd.
	call_deferred("_run")


func _run() -> void:
	await process_frame
	print("--- ENTITY AUTOLOAD REGRESSION TEST ---")

	# 1. The script must load.
	var entity_script = load("res://core/entities/entity.gd")
	if entity_script == null:
		_fail("load entity.gd", "returned null")
		_finish()
		return
	_ok("load() returns the script")

	# 2. .new() must return a real instance with the script attached.
	var e = entity_script.new()
	if e == null:
		_fail("entity_script.new()", "returned null")
		_finish()
		return
	if not (e is Node3D):
		_fail("instance is Node3D", "got " + str(e))
		_finish()
		return
	if e.get_script() != entity_script:
		_fail("script attached", "instance has no script bound")
		_finish()
		return
	_ok(".new() returns a Node3D with the script attached")

	# 3. Default values come from the script.
	if e.display_name != "Entity":
		_fail("default display_name", "got " + str(e.display_name))
	else:
		_ok("default display_name == 'Entity'")

	# 4. Assignment works (proves the script is bound, not a bare Node3D).
	e.display_name = "Test Boss"
	e.entity_id = "boss_001"
	if e.display_name != "Test Boss":
		_fail("display_name assignment", "did not stick")
	else:
		_ok("property assignment sticks")

	# 5. Enum access via the script. This is the same pattern
	#    spawn_service.gd uses: Entity.EntityType.ENEMY.
	if entity_script.EntityType.PLAYER != 1:
		_fail("EntityType.PLAYER", "got " + str(entity_script.EntityType.PLAYER))
	elif entity_script.EntityType.ENEMY != 2:
		_fail("EntityType.ENEMY", "got " + str(entity_script.EntityType.ENEMY))
	elif entity_script.Relation.HOSTILE != 2:
		_fail("Relation.HOSTILE", "got " + str(entity_script.Relation.HOSTILE))
	else:
		_ok("enum access (EntityType.PLAYER=1, ENEMY=2, Relation.HOSTILE=2)")

	# 6. Round-trip the spawn_service.gd pattern: new + set type + set relation.
	#    Note: the field is `relation`, not `faction` (see entity.gd:42).
	var boss = entity_script.new()
	boss.entity_type = entity_script.EntityType.ENEMY
	boss.relation = entity_script.Relation.HOSTILE
	boss.entity_id = "boss_001"
	boss.display_name = "Forest Troll"
	if boss.entity_type != 2:
		_fail("boss.entity_type", "got " + str(boss.entity_type))
	elif boss.relation != 2:
		_fail("boss.relation", "got " + str(boss.relation))
	else:
		_ok("spawn_service.gd pattern: new + EntityType.ENEMY + Relation.HOSTILE")
	boss.queue_free()

	# 7. class_name must be registered globally. The Godot 4 way is to scan
	#    ProjectSettings.get_global_class_list(). Values come back as
	#    StringName, so we convert before comparing.
	var global_classes = ProjectSettings.get_global_class_list()
	var entity_class_registered := false
	for c in global_classes:
		if String(c.get("class")) == "Entity" \
				and String(c.get("path")) == "res://core/entities/entity.gd":
			entity_class_registered = true
			break
	if not entity_class_registered:
		_fail("class_name 'Entity'", "not in global class list")
	else:
		_ok("class_name 'Entity' is registered globally")

	# 8. Entity must NOT be an autoload (the whole point of this test).
	var autoloads := _parse_autoloads("res://project.godot")
	if "Entity" in autoloads:
		_fail("Entity autoload", "Entity is still in [autoload] section of project.godot")
	else:
		_ok("Entity is not an autoload")

	e.queue_free()
	_finish()


# Tiny project.godot parser. Returns the list of autoload names.
# Avoids depending on ProjectSettings because the autoload list is
# not exposed there in 4.7.
func _parse_autoloads(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var in_section := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			in_section = (line == "[autoload]")
			continue
		if not in_section or line.is_empty() or line.begins_with("#"):
			continue
		# Format: Name="*res://path.gd"  (or Name="res://path.gd" for non-singletons)
		var eq := line.find("=")
		if eq < 0:
			continue
		var name := line.substr(0, eq).strip_edges()
		out.append(name)
	f.close()
	return out


func _finish() -> void:
	print("--- RESULTS: ", _passed, " passed, ", _failed, " failed ---")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
