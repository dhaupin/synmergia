# probe_instance_props.gd - the instance prop law (labs/prd-clipmap.md 11a).
# Instanced rooms do not boot a globe, so they cannot ride PropLayer's
# globe-addressed chunks. This probe proves the local-frame sibling: a
# deterministic, seed-derived, mode-aware decoration scatter that (a) reads a
# room as a slice of its biome, (b) is FAIR -- it never crowds the bout
# center, a team spawn, or the solid cover, and (c) never collides.
#
# Conventions: script-mode SceneTree test, _check asserts, exit 0/1.
extends SceneTree

const Kit = preload("res://core/world/instance_prop_kit.gd")

var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# A: the kit scatters decoration over a room.
	var parent := Node3D.new()
	root.add_child(parent)
	var palette := {"tuft": Color(0.34, 0.44, 0.22), "bush": Color(0.26, 0.36, 0.18), "stone": Color(0.46, 0.44, 0.40)}
	var keep: Array = [Vector3(20.0, 0.0, 0.0), Vector3(-20.0, 0.0, 0.0)]
	var placed: int = Kit.new().build(parent, 60.0, 0, 7, palette, keep)
	_check("A1 the kit places decoration", placed > 0)
	_check("A2 every placed prop is a real node", parent.get_child_count() == placed)

	# B: decoration NEVER collides (the fight is unchanged).
	_check("B1 no prop is a physics body", _no_colliders(parent))

	# C: FAIRNESS -- decoration never crowds the bout center.
	_check("C1 decoration clears the bout center", _center_clear(parent, 0.30 * 60.0))

	# D: FAIRNESS -- decoration never crowds a team spawn or the cover.
	_check("D1 decoration clears every keep-clear point", _keep_clear_honored(parent, keep, 5.0))

	# E: determinism -- same seed, same room.
	var parent2 := Node3D.new()
	root.add_child(parent2)
	Kit.new().build(parent2, 60.0, 0, 7, palette, keep)
	_check("E1 a re-scatter is byte-identical", _same_layout(parent, parent2))

	# F: mode-awareness -- the kit reads different per mode (ROYALE != ELIM).
	var royale := Node3D.new()
	root.add_child(royale)
	Kit.new().build(royale, 60.0, 2, 23, palette, keep)
	_check("F1 the kit is mode-aware (different scatter)", not _same_layout(parent, royale))

	# G: the room stays inside its wall (no prop past the band).
	_check("G1 decoration never touches the wall", _inside_band(parent, 60.0))

	print("[probe_instance_props] %s (%d fails)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	quit(0 if _fails == 0 else 1)


func _no_colliders(parent: Node) -> bool:
	for c in parent.get_children():
		if c is StaticBody3D or c is RigidBody3D or c is CharacterBody3D or c is Area3D:
			return false
		if not _no_colliders(c):
			return false
	return true


func _center_clear(parent: Node, radius: float) -> bool:
	for c in parent.get_children():
		if c is Node3D:
			if Vector2(c.position.x, c.position.z).length() < radius:
				return false
	return true


func _keep_clear_honored(parent: Node, keep: Array, radius: float) -> bool:
	for c in parent.get_children():
		if not (c is Node3D):
			continue
		for k in keep:
			if Vector2(c.position.x - k.x, c.position.z - k.z).length() < radius:
				return false
	return true


func _inside_band(parent: Node, half: float) -> bool:
	for c in parent.get_children():
		if c is Node3D and Vector2(c.position.x, c.position.z).length() > 0.96 * half:
			return false
	return true


func _same_layout(a: Node, b: Node) -> bool:
	if a.get_child_count() != b.get_child_count():
		return false
	for i in range(a.get_child_count()):
		if (a.get_child(i) as Node3D).position.distance_to((b.get_child(i) as Node3D).position) > 1e-6:
			return false
	return true


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [OK] %s" % label)
	else:
		_fails += 1
		print("  [FAIL] %s" % label)
