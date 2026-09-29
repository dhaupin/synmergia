## MoonGate -- the S16.3 sealed gate between worlds
## (labs/prd-multiworld.md sec 3, "the clock you wind once a year").
##
## The AncientDoor pattern reprised as a DOOR BETWEEN WORLDS: a
## monolith that stands in the world now, cannot be forced, and waits
## for the tribe. Phase 1 ships the structure + the refusal law; the
## mystery that opens it is the moon's to reveal (TBA by design).
##
## The entry law comes from the lattice, not from this node: the gate
## asks the WorldRegistry (through ScopeService.world_data) whether
## its target world is enterable. OFFLINE/DEV_ONLY worlds are refused
## AS IF THEY DO NOT EXIST -- the underworld has no door, and while
## the moon is DEV_ONLY its gate is the mystery shell: it STANDS in
## the world, it can be read, but it does not complete transit until
## the dev-target flip makes the moon real (S16.6).
##
## Interaction: walk up, press E (the _try_interact path resolves
## "moon_gates" group members). Same {ok, reason, message} contract
## as AncientDoor/concord_stone so the toast pipeline is shared.
##
## Visuals (placeholder geometry, real states): monolith slab with a
## lunar-pale glow strip. Dim = sealed and dark (offline law: this
## way does not exist yet). Pulse = the destination is REAL but the
## mystery is unsolved (the S16.6 state). Transit swaps the world
## scope through ScopeService (the SAME seam as bout/return).
##
## Autoloads resolve lazily from the tree (script-mode safe, the
## blessed_mark pattern): ScopeService, NotificationService.
extends Node3D

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## The world this gate leads to (data/worlds/<world_<id>>.tres id).
@export var target_world: String = "moon"
@export var display_name: String = "Moon Gate"

signal transit_requested(player, world_id: String)
signal transit_completed(player, world_id: String)
signal interact_failed(reason: String)

var _glow: MeshInstance3D = null
var _slab: MeshInstance3D = null
var _pulse_time: float = 0.0
var _registry: Object = null


func _ready() -> void:
	add_to_group("moon_gates")
	_build_visuals()


func _process(delta: float) -> void:
	_pulse_time += delta
	var mat := _glow_mat()
	if mat == null:
		return
	# Two honest states: 0 = dark (the destination is not on any
	# chart), 1 = dim pulse (offline law: the way does not exist
	# yet), 2 = bright pulse (real world, mystery unsolved -- the
	# S16.6 state). Cheap per-frame poll of a pure law, like
	# AncientDoor polling the sky.
	var state := _law_state()
	var pulse := 0.9 + 0.5 * (0.5 + 0.5 * sin(_pulse_time * 2.0))
	if state == 2:
		mat.emission_energy_multiplier = 2.2 + 0.4 * pulse
	elif state == 1:
		mat.emission_energy_multiplier = 0.4 + 0.3 * pulse
	else:
		mat.emission_energy_multiplier = 0.15


## 0 unknown destination, 1 sealed by the entry law, 2 enterable.
func _law_state() -> int:
	var world = _target_data()
	if world == null:
		return 0
	if world.is_enterable():
		return 2
	return 1


## The target WorldData through ScopeService's lazy registry; falls
## back to a direct registry when the autoload is absent (deep
## script-mode). Never a hard dependency: the gate is world content,
## the registry is the law.
func _target_data():
	var scope := get_node_or_null("/root/ScopeService")
	if scope != null and scope.has_method("world_data"):
		return scope.world_data(target_world)
	var reg_script: GDScript = load("res://core/frame/srv/world_registry.gd")
	if reg_script == null:
		return null
	if _registry == null:
		_registry = reg_script.new()
		_registry.load_worlds()
	return _registry.get_world(target_world)


func _glow_mat() -> StandardMaterial3D:
	if _glow == null:
		return null
	return _glow.get_surface_override_material(0) as StandardMaterial3D


## Player-facing moment: what pressing E does here. Returns
## {ok, reason, message} like every other law-gated structure.
func try_interact(player) -> Dictionary:
	var world = _target_data()
	if world == null:
		interact_failed.emit("unknown_world")
		return {"ok": false, "reason": "unknown_world", "message": "The monolith names a place that is not on any chart."}
	# The entry law (WorldData.is_enterable) is the gate's whole
	# truth: no player path to OFFLINE/DEV_ONLY worlds, so the way
	# reads as sealed-by-the-sky, not merely locked.
	if not world.is_enterable():
		interact_failed.emit("sealed")
		var lore: String = str(world.lore).strip_edges()
		if lore == "":
			lore = "The stone is older than the words for it."
		return {"ok": false, "reason": "sealed", "message": "Sealed. %s" % lore}
	return _transit(player)


## The transit: request the world scope swap. On success the player
## renders under the destination world's globe root (radial math, no
## planar flip -- every world is a globe). The S16.6 dev hatch rides
## on the same seam with force=true.
func _transit(player) -> Dictionary:
	transit_requested.emit(player, target_world)
	var scope := get_node_or_null("/root/ScopeService")
	if scope == null or player == null or not ("entity_id" in player):
		# Law passed but no scope path ran (headless/probe without a
		# registered player): honest about the partial success.
		interact_failed.emit("no_scope_path")
		return {"ok": false, "reason": "no_scope_path", "message": "The gate hums, but the way will not open here."}
	var root := _destination_root()
	var pid := str(player.entity_id)
	var swapped: bool = scope.enter_world_scope(pid, target_world, root, false)
	if swapped:
		transit_completed.emit(player, target_world)
		if NotificationService != null:
			NotificationService.notify(
				NotifKind.CUSTOM,
				"The gate takes you. %s fills the sky." % str(_target_data().display_name),
				"MoonGate",
				"moon_gate:transit:%s" % pid,
				{"world": target_world}
			)
		return {"ok": true, "reason": "transit", "message": "The slab takes your weight. %s fills the sky." % str(_target_data().display_name)}
	interact_failed.emit("transit_refused")
	return {"ok": false, "reason": "transit_refused", "message": "The gate hums, but the way will not open here."}


## The destination world's globe root, resolved from the scene the
## gate lives in (the S16.4 moon globe registers itself in the
## "world_root_<id>" group). A null root just fails the swap; the
## player is never stranded by a missing destination.
func _destination_root() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("world_root_" + target_world) as Node3D


func get_interaction_prompt() -> String:
	if _law_state() == 2:
		return "[E] Step through the %s" % display_name
	return "[E] Read the %s" % display_name


## Placeholder visuals: monolith slab + lunar glow strip (same
## placeholder geometry language as AncientDoor; a skinned model
## would drive the same states).
func _build_visuals() -> void:
	if get_node_or_null("Slab") != null:
		_slab = get_node_or_null("Slab") as MeshInstance3D
		_glow = get_node_or_null("Glow") as MeshInstance3D
		return
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(2.2, 4.4, 0.6)
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.42, 0.44, 0.5, 1)
	slab_mat.roughness = 0.7
	slab_mat.metallic = 0.35
	slab_mesh.material = slab_mat
	_slab = MeshInstance3D.new()
	_slab.name = "Slab"
	_slab.mesh = slab_mesh
	_slab.position = Vector3(0, 2.2, 0)
	add_child(_slab)

	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(1.2, 0.16, 0.66)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.8, 0.84, 0.95, 1)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.75, 0.8, 1.0, 1)
	glow_mat.emission_energy_multiplier = 0.4
	glow_mesh.material = glow_mat
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	_glow.mesh = glow_mesh
	_glow.position = Vector3(0, 3.4, 0)
	add_child(_glow)

	# Collision: the world blocks on the gate while the way is sealed.
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 4.4, 0.6)
	shape.shape = box
	shape.position = Vector3(0, 2.2, 0)
	body.add_child(shape)
	add_child(body)
