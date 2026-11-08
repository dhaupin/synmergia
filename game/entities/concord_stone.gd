## ConcordStone -- the physical place where insights happen
## (labs/prd-psy.md section 7, "look-up interaction" slice).
##
## SignService.record_insight() was admin-only before this: the tribal
## reveal loop had no player-facing trigger. A Concord Stone is a
## standing monolith under open sky; press E within range and your
## observation of the current window is recorded. Repeats are
## idempotent (one insight per player per window -- the stone reminds
## you), so it cannot be spammed.
##
## Interaction: walk up, press E (the player body's _try_interact
## resolves the "concord_stones" group the same way it resolves
## ancient_doors and ankhs).
##
## Voice (prd-psy.md law): the stone OBSERVES, it does not bless. No
## ritual worship language -- attention is the reverence this world
## knows.
extends Node3D

## Range at which E resolves this stone (mirrors ancient_doors).
const INTERACT_RANGE: float = 4.0

@export var display_name: String = "Concord Stone"

var _crystal: MeshInstance3D = null
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("concord_stones")
	_build_visuals()


func _process(delta: float) -> void:
	if _crystal == null:
		return
	# Slow breathing pulse: brighter when the current window is already
	# shared knowledge (the tribe has spoken), dim while it waits.
	_pulse_time += delta
	var mat := _crystal.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	var w: Dictionary = SignService.get_current_window() if SignService else {}
	var energy := 0.9 + 0.6 * sin(_pulse_time * 2.0) if bool(w.get("revealed", false)) else 0.35 + 0.15 * sin(_pulse_time * 1.2)
	mat.emission_energy_multiplier = energy


## Player pressed E at this stone. Thin bridge: all state logic lives
## in SignService.record_insight; the stone owns only the fiction and
## the toast payload shape (same contract as AncientDoor.try_interact).
func try_interact(player) -> Dictionary:
	if SignService == null:
		return {"ok": false, "reason": "SignService missing", "message": "The stone is silent."}
	var player_id := ""
	if player != null and "entity_id" in player:
		player_id = str(player.entity_id)
	elif player != null:
		player_id = str(player.get_instance_id())
	var w: Dictionary = SignService.get_current_window()
	var result: Dictionary = SignService.record_insight(player_id)
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": str(result.get("reason", "")), "message": "The stone is silent."}
	if str(result.get("reason", "")) == "already recorded":
		return {
			"ok": true,
			"reason": "already",
			"message": "The stone holds your gaze. %d watching this window." % int(result.get("observers", 1)),
		}
	if bool(result.get("revealed_now", false)):
		return {
			"ok": true,
			"reason": "revealed",
			"message": "The tribe sees it too. Glyph of %s is shared knowledge (%d of 4)." % [str(w.get("sign_name", "")), int(result.get("observers", 0))],
		}
	return {
		"ok": true,
		"reason": "recorded",
		"message": "You mark the %s in the sky. %d of %d watching." % [str(w.get("sign_name", "")), int(result.get("observers", 0)), int(w.get("reveal_threshold", 3))],
	}


## Prompt shown by proximity UI / context menus.
func get_interaction_prompt() -> String:
	return "[E] Watch the sky"


## Placeholder visuals: dark monolith + glowing crystal cap. The cap
## pulses with the window's reveal state (see _process). Real art later;
## state logic already matches what a skinned model would drive.
func _build_visuals() -> void:
	if get_node_or_null("Monolith") != null:
		_crystal = get_node_or_null("Crystal") as MeshInstance3D
		return
	var mono_mesh := BoxMesh.new()
	mono_mesh.size = Vector3(0.7, 2.2, 0.7)
	var mono_mat := StandardMaterial3D.new()
	mono_mat.albedo_color = Color(0.22, 0.26, 0.3, 1)
	mono_mat.roughness = 0.9
	mono_mesh.material = mono_mat
	var mono := MeshInstance3D.new()
	mono.name = "Monolith"
	mono.mesh = mono_mesh
	mono.position = Vector3(0, 1.1, 0)
	add_child(mono)

	var cry_mesh := BoxMesh.new()
	cry_mesh.size = Vector3(0.4, 0.4, 0.4)
	var cry_mat := StandardMaterial3D.new()
	cry_mat.albedo_color = Color(0.4, 0.9, 0.85, 1)
	cry_mat.emission_enabled = true
	cry_mat.emission = Color(0.35, 0.85, 0.8, 1)
	cry_mat.emission_energy_multiplier = 0.35
	cry_mesh.material = cry_mat
	_crystal = MeshInstance3D.new()
	_crystal.name = "Crystal"
	_crystal.mesh = cry_mesh
	_crystal.position = Vector3(0, 2.5, 0)
	add_child(_crystal)

	# Collision so the world blocks on the stone.
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 2.6, 0.7)
	shape.shape = box
	shape.position = Vector3(0, 1.3, 0)
	body.add_child(shape)
	add_child(body)
