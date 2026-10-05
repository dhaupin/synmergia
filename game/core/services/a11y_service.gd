## A11yService - the Accessibility & Agent-Action layer (prd-accessibility.md)
##
## ONE walking snapshot of every actionable Control, in focus order,
## annotated with the engine's native AccessKit properties
## (accessibility_name / accessibility_description on Godot 4.5+).
## Four consumers, one tree: desktop screen readers (AccessKit), web AT
## (AccessKit's web adapter), agents/probes (snapshot()/dump()), and the
## in-world extension (later rounds; same schema).
##
## Design law (PRD sec 4): NO shadow registry. This class WALKS the live
## scene tree on demand. Annotations live on the Controls themselves --
## a side-car would rot the moment someone adds a button and forgets it.
## No per-frame work, ever: snapshots are on-demand walks.
extends Node

## Debounced (0.25s) notice that the actionable set may have changed --
## scene swaps, panels opening/closing, buttons disabling.
signal focusables_changed

var _dirty: bool = false
var _debounce: float = 0.0
var _tree_conn_made: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not _dirty:
		return
	_debounce += delta
	if _debounce >= 0.25:
		_dirty = false
		_debounce = 0.0
		_emit_if_changed()

## Announce AND self-describe: whenever the actionable SET actually
## changes (label signature, not raw node churn -- world-build node
## adds/removes must not spam), emit focusables_changed and dump the
## new set as [A11Y] JSON lines. This is what makes the layer
## "intuitive" for agents: land on any screen, read its actions.
var _last_sig: String = ""

func _emit_if_changed() -> void:
	var snap := snapshot()
	var labels: Array = []
	for entry in snap:
		labels.append(String(entry["action"]))
	var sig := ",".join(labels)
	if sig == _last_sig:
		return
	_last_sig = sig
	for entry in snap:
		print("[A11Y] ", JSON.stringify(entry))
	focusables_changed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and not _tree_conn_made:
		# get_tree() is valid from ENTER_TREE on; connect once, forever.
		get_tree().node_added.connect(_on_tree_mutated)
		get_tree().node_removed.connect(_on_tree_mutated)
		_tree_conn_made = true


func _on_tree_mutated(_node: Node) -> void:
	# Mark only -- do NOT reset the debounce window: services churn
	# nodes every frame (TickService/LOD internals), and a reset-on-
	# mutation debounce starves forever under that churn. Draining at
	# the deadline snapshots whatever the tree looks like THEN; a
	# mutation that lands after a drain re-marks dirty for the next
	# cycle (eventual consistency, ~0.25s late at worst).
	_dirty = true


## Is this control something an agent or AT user can act on right now?
func _is_actionable(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	# Skip the loading overlay family (game-manager's loading canvas):
	# it is chrome around state transitions, not an actionable surface.
	# Skip rule: any control under a CanvasLayer named BootLoadingLayer
	# (GameManager._ensure_boot_loading_overlay's family).
	var ancestor: Node = ctrl
	while ancestor != null:
		if ancestor is CanvasLayer and ancestor.name == "BootLoadingLayer":
			return false
		ancestor = ancestor.get_parent()
	# R36: an EXPLICITLY ANNOTATED control is actionable regardless of
	# kind (CustomSlot PanelContainers, labeled panels); unannotated
	# non-buttons never are. `is` checks, not is_class(): is_class
	# matches the EXACT class name and would miss HSlider/VSlider under
	# "Slider". CheckBox/OptionButton are BaseButton subclasses.
	if "accessibility_name" in ctrl:
		var annotated = ctrl.get("accessibility_name")
		if annotated != null and String(annotated) != "":
			return true
	return ctrl is BaseButton or ctrl is LineEdit or ctrl is ItemList or ctrl is Slider


## The one contract. Ordered (focus = tree) list of actionables:
##   path  : node path (controls) or world/entity:<id> (entities)
##   kind  : engine class or "entity"
##   action: accessibility_name -- the human/agent action label
##   detail: accessibility_description -- the consequence
##   rect  : canvas-space geometry {x,y,w,h} for click-through
##   focused / disabled / visible: current truth
##
## R37 (PRD sec 6): when a local player exists and a world is live,
## entity actions are APPENDED after the UI entries, ordered nearest-
## first, so one snapshot serves the menu AND the world and focus
## order reads as "what is in front of me".
func snapshot() -> Array:
	var out: Array = []
	var root := get_tree().root
	if root == null:
		return out
	# Paths are /root-relative ("MainMenu/MenuButtons/StartButton"):
	# unambiguous, and always resolvable via root.get_node_or_null --
	# current_scene-relative paths break in script-mode tests and
	# during scene swaps.
	_walk(root, "", out)
	_append_world_entries(out)
	return out

## ---- In-world entity actions (PRD sec 6) --------------------------------
## The world is not a second system: InteractionLayer verbs are carried
## into the SAME snapshot schema. Entries are emitted by a bridge (never
## a side-car scan), sorted by screen distance from the cursor/center.
## Focus order in-world = proximity, so TAB cycles world targets the way
## it cycles menu buttons.

const _WORLD_RADIUS := 40.0   # meters of "in front of me"
var _world_sig: String = ""

func _local_player() -> Node:
	var pm = get_node_or_null("/root/PlayerManager")
	if pm != null and "local_player" in pm and pm.local_player != null and is_instance_valid(pm.local_player):
		return pm.local_player
	return null

func _camera() -> Camera3D:
	var player := _local_player()
	if player != null and "camera_pivot" in player:
		var pivot = player.camera_pivot
		if pivot != null and pivot.get_child_count() > 0:
			var cam = pivot.get_child(0)
			if cam is Camera3D:
				return cam
	var vp := get_viewport()
	if vp != null:
		return vp.get_camera_3d()
	return null

## One screen rect per world entity via camera projection (controls
## and entities end up in the same screen space).
func _entity_rect(cam: Camera3D, entity: Node, dist: float = -1.0) -> Dictionary:
	var vp := get_viewport()
	if vp == null:
		return {"x": 0, "y": 0, "w": 0, "h": 0}
	var size: Vector2 = Vector2(56, 56)
	if cam != null and cam.is_inside_tree() and cam.is_current():
		var screen: Vector2 = cam.unproject_position(entity.global_position)
		var x: float = clampf(screen.x - size.x * 0.5, 0, vp.get_visible_rect().size.x)
		var y: float = clampf(screen.y - size.y * 0.5, 0, vp.get_visible_rect().size.y)
		return {"x": x, "y": y, "w": size.x, "h": size.y}
	# Camera-less fallback (script mode / boot edge): a centered rect
	# scaled by distance keeps the entry clickable and the ordering
	# meaningful until a camera exists. Real gameplay always has one.
	var _vp_size: Vector2 = vp.get_visible_rect().size
	var strength: float = clampf(1.0 - (dist if dist > 0 else _WORLD_RADIUS) / _WORLD_RADIUS, 0.3, 1.0)
	var cx: float = _vp_size.x * 0.5
	var cy: float = _vp_size.y * 0.62
	return {"x": cx - size.x * 0.5 * strength, "y": cy - size.y * 0.5 * strength, "w": size.x * strength, "h": size.y * strength}

## The verb: what an agent or player WANTS to do with this thing.
func _entity_verb(entity: Node) -> String:
	# NPC=4, ENEMY=2 (Entity.EntityType values).
	var etype: int = int(entity.entity_type) if "entity_type" in entity else 0
	if "npc_data" in entity and entity.npc_data != null:
		return "Talk"
	if etype == 2:
		return "Attack"
	return "Inspect"

func _append_world_entries(out: Array) -> void:
	var player := _local_player()
	if player == null:
		_world_sig = ""
		return
	var es = get_node_or_null("/root/EntityService")
	if es == null or not es.has_method("get_entities_in_radius"):
		return
	# Camera may legitimately be null mid-swap / in script mode: the
	# distance-scaled fallback rect keeps the bridge alive (real
	# gameplay always has one, and the fallback center sits below the
	# crosshair where world actions belong).
	var cam := _camera()
	var origin: Vector3 = player.global_position
	var entries: Array = []
	# Family codes from Entity.EntityType (entity.gd): ENEMY=2, NPC=4,
	# PLAYER=1. Enemies first (combat is the urgent verb), then NPCs,
	# then players.
	for family in [2, 4, 1]:
		var found: Array = es.get_entities_in_radius(origin, _WORLD_RADIUS, family)
		for entity in found:
			if entity == null or not is_instance_valid(entity):
				continue
			if entity == player:
				continue
			if "is_dead" in entity and bool(entity.is_dead):
				continue
			var label: String = str(entity.display_name) if "display_name" in entity else str(entity.entity_id)
			var dist: float = origin.distance_to(entity.global_position)
			var verb: String = _entity_verb(entity)
			var detail := "%.0fm away" % dist
			if "level" in entity and int(entity.level) > 0:
				detail += ", level %d" % int(entity.level)
			entries.append({
				"path": "world/entity:%s" % str(entity.entity_id),
				"kind": "entity",
				"action": "%s %s" % [verb, label],
				"detail": detail,
				"rect": _entity_rect(cam, entity, dist),
				"focused": false,
				"disabled": false,
				"_dist": dist,
			})
	entries.sort_custom(func(a, b): return float(a["_dist"]) < float(b["_dist"]))
	for e in entries:
		e.erase("_dist")
		out.append(e)
	# Announce world actions when their SET changes (same signature law
	# as the UI announcements).
	var labels: Array = []
	for e in entries:
		labels.append(String(e["action"]))
	var sig := ",".join(labels)
	if sig != _world_sig:
		_world_sig = sig
		for e in entries:
			print("[A11Y] ", JSON.stringify(e))


func _walk(node: Node, base_path: String, out: Array) -> void:
	if node is Control:
		var ctrl := node as Control
		if _is_actionable(ctrl) and ctrl.is_visible_in_tree():
			var entry := {
				"path": _rel_path(ctrl, base_path),
				"kind": ctrl.get_class().to_lower(),
				"action": _action_label(ctrl),
				"detail": _detail_label(ctrl),
				"rect": _rect_dict(ctrl),
				"focused": ctrl.has_focus(),
				"disabled": ctrl.is_disabled() if ctrl is BaseButton else false,
			}
			out.append(entry)
	for child in node.get_children():
		_walk(child, base_path, out)


## One line per actionable as a single JSON object, prefixed for easy
## probe grepping. This is the R35+ e2e contract (replaces all pixel
## archaeology and per-scene geometry dumps).
func dump() -> void:
	var snap := snapshot()
	for entry in snap:
		print("[A11Y] ", JSON.stringify(entry))


## Focus navigation shared by every menu (the three per-menu
## _cycle_focus copies fold onto this). Wraps within the snapshot.
func focus_next() -> bool:
	return _step_focus(1)


func focus_prev() -> bool:
	return _step_focus(-1)


func _step_focus(dir: int) -> bool:
	var snap := snapshot()
	if snap.is_empty():
		return false
	var current_idx := -1
	for i in range(snap.size()):
		if bool(snap[i]["focused"]):
			current_idx = i
			break
	var next_idx := 0 if current_idx == -1 else wrapi(current_idx + dir, 0, snap.size())
	return focus_index(next_idx)


func focus_index(index: int) -> bool:
	var snap := snapshot()
	if index < 0 or index >= snap.size():
		return false
	var path: String = snap[index]["path"]
	var node := _resolve(path)
	if node != null and node is Control:
		(node as Control).grab_focus()
		return true
	return false


## Activate by snapshot index: keyboard activation semantics (button =
## emit pressed; line edit = focus + let the agent type; annotated
## non-buttons = synthesized click, which their gui_input handlers
## handle exactly like a real one). Agents act by name/index here, then
## confirm effects through the game's own logs -- never by bypassing
## the input pipeline.
func activate(index: int) -> bool:
	var snap := snapshot()
	if index < 0 or index >= snap.size():
		return false
	var entry: Dictionary = snap[index]
	if bool(entry["disabled"]):
		return false
	# World entries route through the in-world verbs (R37).
	if String(entry["kind"]) == "entity":
		return _activate_world(entry)
	var node = _resolve(entry["path"])
	if node == null:
		return false
	if node is BaseButton:
		focus_index(index)
		(node as BaseButton).pressed.emit()
		return true
	if node is Control:
		focus_index(index)
		_synthesize_click(node as Control)
		return true
	return false


## Convenience: activate the first actionable whose action label matches
## (exact, case-insensitive). Returns the index used, or -1.
func activate_by_action(action_label: String) -> int:
	var snap := snapshot()
	var wanted := action_label.to_lower()
	for i in range(snap.size()):
		if String(snap[i]["action"]).to_lower() == wanted:
			return i if activate(i) else -1
	return -1


func _resolve(rel_path: String) -> Node:
	var root := get_tree().root
	if root == null:
		return null
	return root.get_node_or_null(rel_path)


func _rel_path(ctrl: Control, _base_path: String) -> String:
	var root := get_tree().root
	return String(ctrl.get_path()).trim_prefix(String(root.get_path()) + "/")


## The action label priority: annotated accessibility_name, else the
## button's own text, else its accessible-name-style node leaf. This is
## what makes un-annotated legacy UI still agent-navigable.
func _action_label(ctrl: Control) -> String:
	if "accessibility_name" in ctrl:
		var annotated = ctrl.get("accessibility_name")
		if annotated != null and String(annotated) != "":
			return String(annotated)
	if ctrl is Button and (ctrl as Button).text != "":
		return (ctrl as Button).text
	if ctrl is LineEdit:
		var le := ctrl as LineEdit
		if le.placeholder_text != "":
			return le.placeholder_text
	return ctrl.name


func _detail_label(ctrl: Control) -> String:
	if "accessibility_description" in ctrl:
		var annotated = ctrl.get("accessibility_description")
		if annotated != null:
			return String(annotated)
	return ""


func _rect_dict(ctrl: Control) -> Dictionary:
	var r := ctrl.get_global_rect()
	return {"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y}


## Synthesized click for annotated non-buttons (skill slots, touch-
## cluster buttons with custom input handlers): press + release at the
## control center, with the viewport focus set so gui_input routing
## matches a real user tap. Nothing bypasses the input pipeline.
func _synthesize_click(ctrl: Control) -> void:
	var rect := ctrl.get_global_rect()
	var center := rect.position + rect.size * 0.5
	var vp := ctrl.get_viewport()
	if vp == null:
		return
	# Hit-test guard: whatever the viewport's pointer path would pick at
	# that point must be (or be inside) the target. An invisible overlay
	# (e.g. a button in a hidden-but-hit-testable CanvasLayer, or a slot
	# whose texture is gone) would otherwise win the pointer pick and
	# the click would vanish -- found by the R36 suite when a hidden
	# BootLoadingLayer button ate a probe click.
	var winner := ctrl.get_viewport().gui_get_hovered_control()
	if winner != null and winner != ctrl and not _is_at_or_above(winner, ctrl, center) and not ctrl.is_ancestor_of(winner):
		return
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = center
	down.global_position = center
	var up: InputEventMouseButton = down.duplicate()
	up.pressed = false
	# Route through the GUI input path explicitly: headless/script-mode
	# viewports only deliver to gui_input handlers when in_gui=true
	# (found by the test suite -- plain push_input dropped the event).
	vp.push_input(down, true)
	vp.push_input(up, true)


## True when `candidate` is the target itself or the target's ancestor
## chain covers the click point (hit-testing delivers to the deepest
## control; ancestors legitimately receive it too).
func _is_at_or_above(candidate: Control, ctrl: Control, _point: Vector2) -> bool:
	var node: Node = candidate
	while node != null:
		if node == ctrl:
			return true
		node = node.get_parent()
	return false


## ---- World-side activation (same pipeline rule: real game verbs) --------

## Resolve a world/entity:<id> snapshot path back to the live node.
func _resolve_world_entity(entity_id: String) -> Node:
	var es = get_node_or_null("/root/EntityService")
	if es == null or not es.has_method("get_entity"):
		return null
	return es.get_entity(entity_id)

## World activation: EVERY verb routes through the game's real combat /
## interaction verbs -- Attack goes through CombatComponent.execute_skill
## (the same gate a player keypress takes), Talk talks, Inspect selects.
## Returns true when a verb executed.
func _activate_world(entry: Dictionary) -> bool:
	var path: String = String(entry["path"])
	if not path.begins_with("world/entity:"):
		return false
	var entity := _resolve_world_entity(path.trim_prefix("world/entity:"))
	if entity == null or not is_instance_valid(entity):
		return false
	var player := _local_player()
	if player == null:
		return false
	var action: String = String(entry["action"])
	if action.begins_with("Attack "):
		# Set the game's own target FIRST (TargetingManager), then cast
		# through the player's skillbar exactly like a keypress: use_skill
		# reads the current target from the targeting pool and routes the
		# skill through CombatComponent (GCD + live stack). No bypass.
		_set_game_target(entity)
		if player.has_method("use_skill"):
			seed(int(Time.get_ticks_msec()) % 100000)
			player.use_skill(0)
			return true
		return false
	if action.begins_with("Talk "):
		if entity.has_method("interact"):
			entity.interact(player)
			return true
		if entity.has_method("_on_interact"):
			entity._on_interact(player)
			return true
		return false
	# Inspect: set the game's own target (the targeting pool), which
	# lights the target frame -- the agent sees the same UI a player does.
	var ok: bool = _set_game_target(entity)
	return true if ok else false

## Set TargetingManager's current target to this entity (rid real UI
## routing: lights the target frame; use_skill reads it for Attack).
func _set_game_target(entity: Node) -> bool:
	var tm = get_node_or_null("/root/TargetingManager")
	if tm == null or not tm.has_method("set_target"):
		return false
	var eid: String = String(entity.entity_id) if "entity_id" in entity else ""
	var sname: String = String(entity.display_name) if "display_name" in entity else eid
	var etype: int = int(entity.entity_type) if "entity_type" in entity else 0
	tm.set_target(eid, eid, sname, entity.global_position, entity, etype, {})
	return true
