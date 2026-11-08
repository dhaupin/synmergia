## BlessedMark -- the shard's chosen class wears the sky's favor
## (labs/prd-psy.md section 8). A drifting ring of sky-cyan motes plus
## a soft halo behind the head, visible only while the wearer's class
## is the wheel's pick AND the day is earned (no solve, no glow).
##
## Distinctness from staff marks is a design rule: GMs are GOLD
## (chat #FFD700, [GM] tag); the sky's favor is SKY-CYAN motes. The
## textual sigil "(*)" rides in front of the title system (see
## TitleService.get_display_name) and in chat, never on GM lines.
##
## Consumers that need the sigil statics or constants PRELOAD this
## file (a fresh class_name would miss the global script cache until
## an editor import pass -- the GuardData lesson). No class_name here.
extends Node3D

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## Sky-cyan: opposite end of the palette from GM gold (#FFD700).
const MOTE_COLOR := Color(0.45, 0.85, 1.0)
## Chat sigil + color for the sky's favor (distinct from [GM] gold).
## Plain text only: chat display names pass through _escape_bbcode,
## which would strip injected markup -- the caller prefixes the sigil
## and swaps the channel color to CHAT_COLOR.
const CHAT_SIGIL := "(*)"
const CHAT_COLOR := "#73D9FF"
## Recheck cadence for live earn-state transitions (day rolls, code
## assembled late in the window). The motes breathe on a separate,
## faster visual clock so rechecks stay cheap.
const RECHECK_INTERVAL: float = 10.0
const MOTE_COUNT: int = 8

signal blessed_state_changed(is_blessed: bool)

var _motes: Array = []
var _halo: MeshInstance3D = null
var _mote_material: StandardMaterial3D = null
var _halo_material: StandardMaterial3D = null
var _visual_time: float = 0.0
var _recheck_time: float = RECHECK_INTERVAL
var _is_blessed: bool = false
var _wearer_class_id: String = ""
## Duck-typed wearer (Node in-game; anything with entity_id in tests).
var _wearer_ref = null


func _ready() -> void:
	_build_visuals()
	visible = false


## Bind to a wearer (the player body or any duck-typed source with
## entity_id -- tests pass plain dictionaries). The class id is copied
## at bind time; a class change rebinds.
func set_wearer(class_id: String, wearer) -> void:
	_wearer_class_id = str(class_id)
	_wearer_ref = wearer
	_recheck_time = RECHECK_INTERVAL
	_refresh_blessed_state()


func get_is_blessed() -> bool:
	return _is_blessed


func _process(delta: float) -> void:
	_recheck_time += delta
	if _recheck_time >= RECHECK_INTERVAL:
		_recheck_time = 0.0
		_refresh_blessed_state()
	if not _is_blessed:
		return
	_visual_time += delta
	_breathe()


## Truth check: SignService.is_class_blessed resolves both halves of
## the rule (wheel pick + earned day). Fades in/out on the edge and
## announces once per transition. Autoloads resolve LATE via the main
## loop: this file is preloaded at parse time by services/tests, where
## bare autoload identifiers do not exist yet (--script reality).
func _refresh_blessed_state() -> void:
	var blessed: bool = false
	var svc = _resolve_service("SignService")
	if not _wearer_class_id.is_empty() and svc != null \
			and svc.has_method("is_class_blessed"):
		blessed = svc.is_class_blessed(_wearer_class_id)
	if blessed == _is_blessed:
		return
	_is_blessed = blessed
	_apply_visibility(false)
	blessed_state_changed.emit(blessed)
	var nsvc = _resolve_service("NotificationService")
	if nsvc != null and _wearer_ref != null \
			and "entity_id" in _wearer_ref:
		var pid := str(_wearer_ref.entity_id)
		if not pid.is_empty():
			nsvc.notify(
				NotifKind.CUSTOM,
				"The sky's favor settles on you -- your class is the wheel's pick today.",
				"BlessedMark",
				"blessed:mark:%s:%s" % [pid, "on" if blessed else "off"],
				{"player_id": pid, "blessed": blessed},
				pid
			)


## Fade the motes/halo. Instant snaps (attach-time or off-tree) skip
## the tween -- create_tween needs the node inside the tree.
func _apply_visibility(instant: bool) -> void:
	if not is_inside_tree():
		instant = true
	visible = _is_blessed
	var energy := 1.6 if _is_blessed else 0.0
	if instant:
		if _mote_material != null:
			_mote_material.emission_energy_multiplier = energy
		if _halo_material != null:
			_halo_material.emission_energy_multiplier = energy * 0.4
		return
	var tween := create_tween()
	tween.set_parallel(true)
	if _mote_material != null:
		tween.tween_property(_mote_material, "emission_energy_multiplier", energy, 1.2)
	if _halo_material != null:
		tween.tween_property(_halo_material, "emission_energy_multiplier", energy * 0.4, 1.2)


## The motes orbit slowly and breathe; the halo pulses with them.
func _breathe() -> void:
	var breath := 0.75 + 0.25 * sin(_visual_time * 1.6)
	if _mote_material != null:
		_mote_material.emission_energy_multiplier = 1.6 * breath
	if _halo_material != null:
		_halo_material.emission_energy_multiplier = 0.64 * breath
	var radius := 0.85 + 0.06 * sin(_visual_time * 0.8)
	for i in _motes.size():
		var mote: MeshInstance3D = _motes[i]
		if mote == null:
			continue
		var angle: float = _visual_time * 0.9 + TAU * float(i) / float(_motes.size())
		mote.position = Vector3(cos(angle) * radius, 1.35 + 0.12 * sin(_visual_time * 2.0 + float(i)), sin(angle) * radius)


## Placeholder visuals (the door/stone pattern): eight small motes in
## a ring + a soft flattened halo behind the head. Real art later; the
## state logic already matches what a skinned VFX would drive.
func _build_visuals() -> void:
	if not _motes.is_empty() or _halo != null:
		return
	_mote_material = StandardMaterial3D.new()
	_mote_material.albedo_color = MOTE_COLOR
	_mote_material.emission_enabled = true
	_mote_material.emission = MOTE_COLOR
	_mote_material.emission_energy_multiplier = 0.0
	var mote_mesh := SphereMesh.new()
	mote_mesh.radius = 0.05
	mote_mesh.height = 0.1
	for i in MOTE_COUNT:
		var mote := MeshInstance3D.new()
		mote.name = "Mote%d" % i
		mote.mesh = mote_mesh
		mote.material_override = _mote_material
		add_child(mote)
		_motes.append(mote)

	_halo_material = StandardMaterial3D.new()
	_halo_material.albedo_color = MOTE_COLOR
	_halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_material.albedo_color.a = 0.35
	_halo_material.emission_enabled = true
	_halo_material.emission = MOTE_COLOR
	_halo_material.emission_energy_multiplier = 0.0
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 0.34
	halo_mesh.height = 0.5
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = halo_mesh
	_halo.material_override = _halo_material
	_halo.position = Vector3(0, 1.75, -0.18)
	add_child(_halo)


# ------------------------------------------------------------------
# Static sigil helpers (chat + title prefix). Statics resolve the
# autoload late -- parse-time bare identifiers would break --script
# compilation of this file (the CombatMath lesson).
# ------------------------------------------------------------------

## Is this class the wheel's pick on an earned day, right now?
static func is_class_blessed_now(class_id: String) -> bool:
	var cid := str(class_id)
	if cid.is_empty():
		return false
	var svc = _resolve_service("SignService")
	if svc == null or not svc.has_method("is_class_blessed"):
		return false
	return svc.is_class_blessed(cid)


## Late autoload resolution (the CombatMath static pattern): parse-
## time bare identifiers do not exist for preloaded scripts.
static func _resolve_service(name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null(name)


## The "(*)" sigil for a blessed class, "" otherwise. Rides IN FRONT
## of the title prefix (TitleService.get_display_name composes it).
static func sigil_for_class(class_id: String) -> String:
	return CHAT_SIGIL if is_class_blessed_now(class_id) else ""
