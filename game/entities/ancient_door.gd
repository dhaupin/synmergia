## AncientDoor -- the consuming side of the Skyward Concord
## (labs/prd-psy.md section 7). A server-wide door/vault that opens
## only when SignService reports its day's Ancient as unlocked (the
## previous day's four glyphs were revealed by the community).
##
## The loop: look up -> record insight -> tribe reveals 4 windows ->
## tomorrow's Ancient unlocks -> this door physically opens for everyone.
##
## Interaction: walk up, press E (the player body's _try_interact
## resolves "ancient_doors" group members the same way it resolves
## ankhs). No combat, no keys: the code is in the SKY, and the
## unlock is server-wide -- the door is the payoff moment, not a gate
## any individual holds.
##
## Visual: a monolith slab (placeholder box) that sinks into the ground
## on unlock. A glow strip shows the door's state: dim = sealed,
## pulsing amber = unlocked-but-closed (someone must walk up and claim
## it), green = open.
##
## Re-seal: the door tracks ONE day (today + for_day_offset). At the
## next dawn the day it names moves forward and the unlock behind it
## stops being true, so the slab rises again -- daily urgency, no
## permanent unlocks. That reset was documented here and never
## implemented (the slab stayed sunken forever, so door_opened fired
## once per server lifetime); the Acts batch closed the gap.
extends Node3D

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## Which day's Ancient this door tracks, relative to today. Default 1
## = TOMORROW's Ancient (the Concord fiction: completing today's code
## "turns the key" on the door that stands in the world NOW -- the
## payoff lands the moment the tribe reveals the fourth glyph). The
## door re-seals at the next dawn when it starts naming the NEXT
## Ancient: daily urgency, no permanent unlocks. A fixed day pins a
## specific unlock for special content (seasonal ruins, act
## milestones); 0 would track today, which only opens if YESTERDAY's
## code completed.
@export var for_day_offset: int = 1
@export var display_name: String = "Ancient Door"

signal door_opened(day_index: int)
signal interact_failed(reason: String)

## S16.5 world-state law: the door's open/re-seal are WORLD DELTAS,
## recorded with provenance (actor = door, epoch = the sky clock) in
## the same StateTree everything else writes. Re-seal is an ERASURE
## delta: the record is replaced by {cleared: true} so the audit
## trail answers who opened and when the way closed.
const WorldStateProjectionScript = preload("res://core/services/world_state_projection.gd")

var _is_open: bool = false
var _last_known_unlocked: bool = false
var _glow: MeshInstance3D = null
var _slab: MeshInstance3D = null
var _pulse_time: float = 0.0
## The day whose unlock opened the door (-1 = none). Cleared on re-seal
## so the same day cannot re-open it after dawn.
var _last_unlock_day: int = -1
var _slab_home: Vector3 = Vector3(0, 1.4, 0)


func _ready() -> void:
	add_to_group("ancient_doors")
	_build_visuals()
	_refresh_state()


func _process(delta: float) -> void:
	# Unlock flips at the day boundary without any door-side timer; a
	# cheap per-frame refresh keeps the visuals honest. The actual open
	# transition fires only on the false->true edge.
	_refresh_state()
	if _glow != null:
		_pulse_time += delta
		var mat := _glow.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			if _is_open:
				mat.emission_energy_multiplier = 2.2
			elif _last_known_unlocked:
				# Amber pulse: unlocked but not yet walked up to.
				mat.emission_energy_multiplier = 1.2 + 0.8 * (0.5 + 0.5 * sin(_pulse_time * 3.0))
			else:
				mat.emission_energy_multiplier = 0.4


## Resolve which day this door tracks: today + offset (offset 0 = today).
func _resolve_day() -> int:
	if SignService == null:
		return -1
	return SignService.day_index_for(float(Time.get_unix_time_from_system())) + for_day_offset


## Poll SignService and run the false->true open transition.
func _refresh_state() -> void:
	if SignService == null:
		return
	var day := _resolve_day()
	if day < 0:
		return
	var unlocked: bool = SignService.is_ancient_unlocked(day)
	_last_known_unlocked = unlocked
	if unlocked and not _is_open:
		_open(day)
		return
	# Dawn re-seal: the day this door names moved past the unlock that
	# opened it, so the way closes until the tribe earns the next key.
	if _is_open and not unlocked:
		_is_open = false
		_last_unlock_day = -1
		_reseal()
		GameLog.info("AncientDoor: %s re-sealed at dawn" % display_name)


func _open(day: int) -> void:
	_is_open = true
	_last_unlock_day = day
	_play_open_animation()
	_play_payoff_effects()
	if NotificationService:
		NotificationService.notify(
			NotifKind.ANCIENT_OPEN,
			"%s has opened. The tribe's watching paid the debt." % display_name,
			"AncientDoor",
			"ancient:open:%d" % day,
			{"day_index": day, "door": name}
		)
	door_opened.emit(day)
	_record_world_delta(false, day)
	GameLog.info("AncientDoor: %s opened for day %d" % [display_name, day])


## The reveal moment: the slab sinks into the ground.
func _play_open_animation() -> void:
	if _slab == null:
		return
	var tween := create_tween()
	tween.tween_property(_slab, "position:y", _slab_home.y - 2.4, 2.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## The shard-wide payoff (labs/prd-psy.md section 9): an amber light
## pillar erupts from the slab (visible across the playable world),
## the ceremonial bell rings everywhere, and a one-shot OmniLight
## flash blooms at the door. Purely additive visuals -- the state
## machine above is untouched by anything here.
func _play_payoff_effects() -> void:
	# The bell: communal sound, non-positional (AudioService pool).
	var audio = get_node_or_null("/root/AudioService")
	if audio != null and audio.has_method("play_world"):
		audio.play_world("ancient_door_open", 0.0)
	# The sky acknowledges: amber wash over the whole constellation.
	var sky: Node = null
	if get_tree() != null:
		sky = get_tree().get_first_node_in_group("sky_signs")
	if sky != null and sky.has_method("flash_payoff"):
		sky.flash_payoff(3.0)
	# The pillar: emissive cylinder, taller than any structure.
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.55
	pillar_mesh.bottom_radius = 0.7
	pillar_mesh.height = 30.0
	pillar_mesh.radial_segments = 12
	pillar_mesh.cap_top = false
	pillar_mesh.cap_bottom = false
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(1.0, 0.72, 0.28, 0.5)
	pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pillar_mat.emission_enabled = true
	pillar_mat.emission = Color(1.0, 0.7, 0.25)
	pillar_mat.emission_energy_multiplier = 3.0
	pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pillar := MeshInstance3D.new()
	pillar.name = "PayoffPillar"
	pillar.mesh = pillar_mesh
	pillar.material_override = pillar_mat
	pillar.position = Vector3(0, 15.0, 0)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pillar)
	# A one-shot light flash blooming with the pillar.
	var flash := OmniLight3D.new()
	flash.name = "PayoffFlash"
	flash.light_color = Color(1.0, 0.75, 0.3)
	flash.light_energy = 0.0
	flash.omni_range = 14.0
	flash.position = Vector3(0, 2.2, 0)
	add_child(flash)
	# Ramp the bloom up, hold the pillar ~4s, then fade both and clean
	# up (the pillar is one-shot; the door stays open, not glowing).
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "light_energy", 2.2, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pillar_mat, "emission_energy_multiplier", 4.0, 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(2.8)
	tween.chain().tween_property(pillar_mat, "emission_energy_multiplier", 0.0, 1.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(flash, "light_energy", 0.0, 1.8)
	tween.chain().tween_callback(func():
		if is_instance_valid(pillar):
			pillar.queue_free()
		if is_instance_valid(flash):
			flash.queue_free())


## The dawn moment: the slab rises again (inverse of _play_open_animation).
func _reseal() -> void:
	_record_world_delta(true, _last_unlock_day)
	if _slab != null:
		_slab.position = _slab_home
	var mat: StandardMaterial3D = null
	if _glow != null:
		mat = _glow.get_surface_override_material(0) as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = 0.4


## The player-facing moment: what pressing E does here.
## Returns a result Dictionary {ok, reason, message} for tests + prompts.
func try_interact(player) -> Dictionary:
	if SignService == null:
		return {"ok": false, "reason": "SignService missing", "message": "The door is silent."}
	var day := _resolve_day()
	if day < 0:
		return {"ok": false, "reason": "no day", "message": "The door is silent."}
	if _is_open:
		var code_today: String = SignService.get_ancient_code(day - 1)
		return {"ok": true, "reason": "already_open", "message": "The way is open. Yesterday the sky read: %s" % code_today}
	if SignService.is_ancient_unlocked(day):
		_open(day)
		return {"ok": true, "reason": "opened", "message": "The slab sinks. The tribe's code was true."}
	# Sealed: tell the player WHERE the truth lives, not the code itself.
	var w: Dictionary = SignService.get_current_window()
	var glyphs: Array[String] = SignService.get_revealed_glyphs()
	var known := 0
	for g in glyphs:
		if g != "?":
			known += 1
	var msg := "Sealed. The sky holds the code -- your tribe has read %d of 4 glyphs. %s" % [known, str(w.get("sign_name", ""))]
	interact_failed.emit("sealed")
	return {"ok": false, "reason": "sealed", "message": msg}


## Prompt shown by proximity UI / context menus.
func get_interaction_prompt() -> String:
	if _is_open:
		return "[E] The Ancient lies open"
	if SignService != null and _last_known_unlocked:
		return "[E] Wake the Ancient"
	return "[E] Read the Ancient Door"


## Placeholder visuals: monolith slab + glow strip. Replaced by real
## art later; the state logic already matches what a skinned model
## would drive (slab sink + strip emission).
func _build_visuals() -> void:
	if get_node_or_null("Slab") != null:
		_slab = get_node_or_null("Slab") as MeshInstance3D
		_glow = get_node_or_null("Glow") as MeshInstance3D
		if _slab != null:
			_slab_home = _slab.position
		return
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(1.6, 2.8, 0.5)
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.28, 0.3, 0.34, 1)
	slab_mat.roughness = 0.85
	slab_mat.metallic = 0.2
	slab_mesh.material = slab_mat
	_slab = MeshInstance3D.new()
	_slab.name = "Slab"
	_slab.mesh = slab_mesh
	_slab.position = _slab_home
	add_child(_slab)

	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(1.0, 0.12, 0.56)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.9, 0.6, 0.2, 1)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.95, 0.65, 0.2, 1)
	glow_mat.emission_energy_multiplier = 0.4
	glow_mesh.material = glow_mat
	_glow = MeshInstance3D.new()
	_glow.name = "Glow"
	_glow.mesh = glow_mesh
	_glow.position = Vector3(0, 1.4, 0)
	add_child(_glow)

	# Collision so the world blocks on the door while sealed.
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.8, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 1.4, 0)
	body.add_child(shape)
	add_child(body)


## S16.5: open/re-seal become world deltas under gates/<door>. The
## epoch is the canonical sky clock (S16.2's single sky time), the
## actor is this door -- the delta ledger is the audit trail for
## "when did the way stand open?" Defensive: no projection (deep
## script mode) skips the write; a door still opens.
func _record_world_delta(cleared: bool, day: int) -> void:
	var proj = get_node_or_null("/root/WorldStateProjection")
	if proj == null or not proj.has_method("world_state"):
		return
	var ws = proj.world_state()
	var epoch: float = -1.0
	if SignService != null and SignService.has_method("sky_epoch_days"):
		epoch = SignService.sky_epoch_days()
	var payload: Dictionary = {"opened_for_day": day} if not cleared else {"cleared": true, "resealed": true}
	var key: String = "gates/%s" % str(name)
	if cleared:
		ws.erase_world_state("main", key, str(name), epoch)
	else:
		ws.set_world_state("main", key, payload, str(name), epoch)
