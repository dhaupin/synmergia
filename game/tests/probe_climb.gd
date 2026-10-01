## One-shot probe: prop colliders + the BotW-style climb law.
## A. PropCollider.attach_trunk builds a slim climbable body on a tree.
## B. PropCollider.attach auto-sizes a body from mesh AABBs.
## C. The globe player's climb constants/state exist; _wall_ahead
##    returns ZERO with no wall and engages via the physics query when
##    a climbable body is in reach.
extends SceneTree

var _checks := 0


func _check(label: String, cond: bool) -> bool:
	_checks += 1
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var PC = load("res://entities/prop_collider.gd")

	# --- A. Trunk collider on a synthetic tree ---------------------------
	var tree := Node3D.new()
	tree.name = "Tree0"
	root.add_child(tree)
	var trunk := MeshInstance3D.new()
	trunk.name = "trunk"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.14
	cm.bottom_radius = 0.22
	cm.height = 2.5
	trunk.mesh = cm
	tree.add_child(trunk)
	var canopy := MeshInstance3D.new()
	canopy.name = "canopy"
	var sm := SphereMesh.new()
	sm.radius = 1.5
	canopy.mesh = sm
	canopy.position = Vector3(0, 3.0, 0)
	tree.add_child(canopy)

	var body = PC.attach_trunk(tree)
	ok = _check("trunk body attached", body != null and is_instance_valid(body)) and ok
	ok = _check("body is on the climbable group", body.is_in_group("climbable")) and ok
	ok = _check("body on layer 2 only", int(body.collision_layer) == 2) and ok
	var col: CollisionShape3D = body.get_child(0)
	ok = _check("trunk shape is slim (canopy excluded)", \
		(col.shape as CylinderShape3D).radius < 0.5 \
		and (col.shape as CylinderShape3D).height < 3.0) and ok
	# Idempotent
	var again = PC.attach_trunk(tree)
	ok = _check("attach_trunk idempotent", again == body) and ok

	# --- B. Auto-sized attach --------------------------------------------
	var rock := Node3D.new()
	rock.name = "BigRock"
	root.add_child(rock)
	var rm := MeshInstance3D.new()
	var rshape := BoxMesh.new()
	rshape.size = Vector3(3.0, 2.5, 3.0)
	rm.mesh = rshape
	rock.add_child(rm)
	var rbody = PC.attach(rock)
	ok = _check("auto attach sizes from mesh", rbody != null \
		and absf((rbody.get_child(0) as CollisionShape3D).shape.size.y - 2.5) < 0.01) and ok

	# --- C. Climb law state on the player --------------------------------
	var GP = load("res://entities/globe_player.gd")
	var player: CharacterBody3D = GP.new()
	player.name = "ClimbProbePlayer"
	root.add_child(player)
	await process_frame  # _ready sets the default layer/mask
	ok = _check("player has climb stamina pool", \
		absf(player.climb_stamina - GP.CLIMB_STAMINA_MAX) < 0.001) and ok
	ok = _check("player collides with the props layer", \
		int(player.collision_mask) & 2 != 0) and ok
	player.collision_layer = 1
	# _wall_ahead with nothing around: ZERO (no wall in reach).
	var up := Vector3.UP
	var wall: Vector3 = player._wall_ahead(up, Vector3.FORWARD)
	ok = _check("no wall in open space", wall == Vector3.ZERO) and ok
	# A climbable body directly ahead within reach: the probe ray (mask 2)
	# hits its PropBody and returns a steep normal.
	var wall_prop := Node3D.new()
	root.add_child(wall_prop)
	wall_prop.global_position = player.global_position + Vector3.FORWARD * 1.2
	var wbody = PC.attach(wall_prop)
	var wcol: CollisionShape3D = wbody.get_child(0)
	(wcol.shape as BoxShape3D).size = Vector3(2.0, 4.0, 0.5)
	wcol.position = Vector3(0, 2.0, 0)
	await physics_frame
	await physics_frame
	wall = player._wall_ahead(up, Vector3.FORWARD)
	ok = _check("climbable wall detected within reach", wall != Vector3.ZERO) and ok
	if wall != Vector3.ZERO:
		ok = _check("wall normal is steep (not a floor)", absf(wall.dot(up)) < 0.5) and ok

	if ok:
		print("PASS: prop colliders + climb law (%d checks)" % _checks)
		quit(0)
	else:
		push_error("FAIL: prop colliders + climb law")
		quit(1)
