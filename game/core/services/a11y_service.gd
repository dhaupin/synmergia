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
	# `is` checks, not is_class(): is_class matches the EXACT class name
	# and would miss HSlider/VSlider under "Slider". CheckBox/OptionButton
	# are BaseButton subclasses and ride along for free.
	return ctrl is BaseButton or ctrl is LineEdit or ctrl is ItemList or ctrl is Slider


## The one contract. Ordered (focus = tree) list of actionables:
##   path  : node path from the scene root (stable machine key)
##   kind  : engine class (button / line_edit / ...)
##   action: accessibility_name -- the human/agent action label
##   detail: accessibility_description -- the consequence
##   rect  : canvas-space geometry {x,y,w,h} for click-through
##   focused / disabled / visible: current truth
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
	return out


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
## emit pressed; line edit = focus + let the agent type). Agents act by
## name/index here, then confirm effects through the game's own logs --
## never by bypassing the input pipeline.
func activate(index: int) -> bool:
	var snap := snapshot()
	if index < 0 or index >= snap.size():
		return false
	var entry: Dictionary = snap[index]
	if bool(entry["disabled"]):
		return false
	var node = _resolve(entry["path"])
	if node == null:
		return false
	if node is BaseButton:
		focus_index(index)
		(node as BaseButton).pressed.emit()
		return true
	if node is Control:
		focus_index(index)
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
