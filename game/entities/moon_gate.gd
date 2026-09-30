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
const WorldRegistry = preload("res://core/frame/srv/world_registry.gd")

## The world this gate leads to (data/worlds/<world_<id>>.tres id).
@export var target_world: String = "moon"
@export var display_name: String = "Moon Gate"

## The destination globe scene conjured at transit time. Empty = the
## convention path (res://scenes/worlds/globe_<target_world>.tscn --
## the Scene & World naming law). S15.2: the underworld sets its own
## scene; the moon keeps the convention.
@export var destination_scene: String = ""

## The transfer-window law (S16.5): this gate opens only in a
## FAVORABLE SKY -- the closed-form phase alignment between the
## origin and destination worlds (WorldRegistry.window_favorability,
## 0.0 = perfect alignment). Threshold 0.25 = within a quarter of the
## alignment angle; the almanac page reads the same math, so what the
## stone says and what the chart says can never disagree.
@export var window_law: bool = true
@export var window_threshold: float = 0.25

## S16.6 dev hatch: THIS gate completes transit to DEV_ONLY worlds
## (the dev-target flip -- the moon hosts the dev work so the main
## world stays clean). Default false: a default gate is still the
## sealed mystery shell (the entry law reads DEV_ONLY as no door).
## The hatch also bypasses the window law: dev work does not wait
## for the sky (and the probe must be able to pin time without the
## moon's orbit period making windows flaky).
@export var dev_hatch: bool = false

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
## The dev hatch lifts a DEV_ONLY destination to 2 FOR THIS GATE
## (the way is real; the world is still not a player world).
func _law_state() -> int:
	var world = _target_data()
	if world == null:
		return 0
	if world.is_enterable():
		return 2
	if dev_hatch and int(world.offline) == 2:
		return 2
	return 1


## The S16.5 window law: is the sky favorable RIGHT NOW? Pure read
## of the closed-form phase alignment on the live Concord epoch
## (override-aware: admin time travel moves the windows). Non-orbit
## pairs are always favorable (favorability 1.0 fails the check --
## so the origin/dest pair MUST both be in the lattice and at least
## one must orbit; a gate to a static pair has no sky to read).
## Returns {open: bool, favorability: float, message: String}.
func window_status() -> Dictionary:
	var origin = _world_of_origin()
	var dest = _target_data()
	if origin == null or dest == null:
		return {"open": false, "favorability": 1.0, "message": "The sky names neither world."}
	var fav: float = WorldRegistry.window_favorability(origin, dest, _epoch_days())
	if fav <= window_threshold:
		return {"open": true, "favorability": fav, "message": "The sky aligns."}
	var next_e: float = WorldRegistry.next_transfer_window(origin, dest, _epoch_days(), window_threshold)
	var days_ahead: float = next_e - _epoch_days()
	return {"open": false, "favorability": fav, "message": \
		"The sky is against it (%.0f%% aligned). Next window in %.1f days." % [(1.0 - fav) * 100.0, maxf(days_ahead, 0.0)]}


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
## Law order: ENTRY first (does the way exist at all), then WINDOW
## (is the sky favorable now). The dev hatch bypasses both -- dev
## work does not wait for the sky.
func try_interact(player) -> Dictionary:
	var world = _target_data()
	if world == null:
		interact_failed.emit("unknown_world")
		return {"ok": false, "reason": "unknown_world", "message": "The monolith names a place that is not on any chart."}
	# The entry law (WorldData.is_enterable) is the gate's whole
	# truth: no player path to OFFLINE/DEV_ONLY worlds, so the way
	# reads as sealed-by-the-sky, not merely locked. The dev hatch is
	# the S16.6 exception FOR THIS GATE (DEV_ONLY only -- OFFLINE
	# worlds like the underworld stay doorless for everyone).
	var entry_open: bool = world.is_enterable() or (dev_hatch and int(world.offline) == 2)
	if not entry_open:
		interact_failed.emit("sealed")
		var lore: String = str(world.lore).strip_edges()
		if lore == "":
			lore = "The stone is older than the words for it."
		return {"ok": false, "reason": "sealed", "message": "Sealed. %s" % lore}
	# The window law (S16.5): the way exists; the sky must agree.
	# The hatch bypasses it (dev work does not wait for the moon).
	if window_law and not dev_hatch:
		var win := window_status()
		if not bool(win.get("open")):
			interact_failed.emit("unfavorable_sky")
			return {"ok": false, "reason": "unfavorable_sky", "message": str(win.get("message"))}
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
	var world = _target_data()
	var pid := str(player.entity_id)
	_ensure_home_root()
	# S16.6 DEV FLIP: a DEV_ONLY world conjures its globe at transit
	# time -- the moon exists because someone chose to go. The
	# conjured root registers in "world_root_<id>" so the return gate
	# resolves home. OFFLINE worlds never reach this line (the entry
	# law refused them already: no door).
	var root := _destination_root()
	if root == null and not bool(world.is_enterable()) and str(world.offline) == "2":
		root = _conjure_destination(player)
	if root == null:
		interact_failed.emit("transit_refused")
		return {"ok": false, "reason": "transit_refused", "message": "The gate hums, but the way will not open here."}
	# The dev hatch rides the SAME seam the entry law guards: players
	# through an ONLINE gate swap with force=false; a DEV_ONLY
	# destination needs the hatch (force=true) because the law still
	# says the moon is not a player world.
	var needs_hatch: bool = not bool(world.is_enterable())
	var swapped: bool = scope.enter_world_scope(pid, target_world, root, needs_hatch)
	if swapped:
		_adapt_visitor(player, root)
		transit_completed.emit(player, target_world)
		if NotificationService != null:
			NotificationService.notify(
				NotifKind.CUSTOM,
				"The gate takes you. %s fills the sky -- welcome to the workshop." % str(_target_data().display_name),
				"MoonGate",
				"moon_gate:transit:%s" % pid,
				{"world": target_world}
			)
		return {"ok": true, "reason": "transit", "message": "The slab takes your weight. %s fills the sky." % str(_target_data().display_name)}
	interact_failed.emit("transit_refused")
	return {"ok": false, "reason": "transit_refused", "message": "The gate hums, but the way will not open here."}


## Conjure the destination globe (dev targets). Loads the world scene
## by path (the GuardData lesson: no class_name for a fresh script),
## parents it under the COMMON ancestor of this gate and the player
## so it survives scope swaps, and receives the visitor. Scene
## resolution: the explicit destination_scene export wins; otherwise
## the naming convention (globe_<target_world>.tscn) -- a new world
## with a conforming scene needs no gate code at all.
func _conjure_destination(player) -> Node3D:
	var scene_path := destination_scene
	if scene_path.is_empty():
		scene_path = "res://scenes/worlds/globe_%s.tscn" % target_world
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return null
	var globe := packed.instantiate()
	if globe == null:
		return null
	var holder := _conjure_holder()
	holder.add_child(globe)
	var root: Node3D = globe.get("world_root")
	return root


## Where conjured worlds live: the current SCENE (never this gate --
## a freed gate must not take the moon with it).
func _conjure_holder() -> Node:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return get_parent()
	return tree.current_scene


## Adopt the visitor into the destination's physics (the conjured
## globe binds the body: lunar gravity, no wing, landing placement).
## The main world's planar PlayerController has no planet_center/
## planet_radius (it walks the classic world); the moon globe binds
## only what the body actually has. The body's world_id drives the
## per-world gravity law (S16.4) and the vacuum wing gate.
func _adapt_visitor(player, root: Node3D) -> void:
	var globe := root.get_parent()
	if globe != null and globe.has_method("receive_visitor"):
		globe.receive_visitor(player)


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
		# The window law speaks in the prompt too (the stone is a
		# chart): favorable = step through; unfavorable = read and
		# wait (the message carries the next window). The hatch
		# BYPASSES the window for transit but the stone still SPEAKS
		# the sky -- a chart that lies by omission is no chart.
		if window_law:
			var win := window_status()
			if bool(win.get("open")):
				return "[E] Step through the %s (the sky aligns)" % display_name
			if not dev_hatch:
				return "[E] Read the %s" % display_name
			return "[E] Step through the %s (against the sky -- dev)" % display_name
		return "[E] Step through the %s" % display_name
	return "[E] Read the %s" % display_name


## The gate reads the sky on the Concord epoch (override-aware:
## admin time travel moves the windows with the calendar -- the
## one-clock law).
func _epoch_days() -> float:
	var svc = get_node_or_null("/root/SignService")
	if svc != null and svc.has_method("sky_epoch_days"):
		return svc.sky_epoch_days()
	return float(Time.get_unix_time_from_system()) / 86400.0


## The world the STANDER is on (the window law is a relation between
## two worlds). Falls back to the main world: the boot world is main
## and every current route stands there.
func _world_of_origin():
	var scope = get_node_or_null("/root/ScopeService")
	if scope != null and scope.has_method("world_data"):
		var origin_id: String = "main"
		var pm = get_node_or_null("/root/PlayerManager")
		if pm != null:
			var local = pm.get("local_player")
			if local != null and is_instance_valid(local) and scope.has_method("world_of"):
				origin_id = scope.world_of(str(local.get("entity_id")))
		return scope.world_data(origin_id)
	# Deep script mode: the main declaration directly.
	var reg_script: GDScript = load("res://core/frame/srv/world_registry.gd")
	if reg_script == null:
		return null
	if _registry == null:
		_registry = reg_script.new()
		_registry.load_worlds()
	return _registry.get_world("main")


## The moon globe's return gate stands on CONJURED ground: its
## destination root is the main scene itself. Register the boot
## scene's root in "world_root_main" when the holder is the live
## playable world so _destination_root resolves from anywhere.
func _ensure_home_root() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	if tree.get_first_node_in_group("world_root_main") != null:
		return
	tree.current_scene.add_to_group("world_root_main")


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
