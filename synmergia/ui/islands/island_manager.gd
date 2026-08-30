## Mount orchestrator for the Islands system.
##
## Scans the scene tree under [param root] for [IslandPlaceholder] nodes
## and replaces each one with the registered [PackedScene] according to
## the placeholder's [code]load_strategy[/code]:
##
## [b]eager[/b]   -- mount immediately, synchronously
## [b]visible[/b] -- mount when the placeholder enters the viewport
## [b]idle[/b]    -- mount during the next idle frame
##
## Idempotent: a placeholder is mounted at most once. Safe to call
## multiple times for the same scene.
##
## Used by [code]GameManager[/code] after a scene transition, or by
## [code]ZoneManager[/code] after a zone change. No autoload
## dependencies on Entity / Inventory / Party etc. -- this is leaf-level.
class_name IslandManager
extends Node

const _STRATEGY_EAGER := "eager"
const _STRATEGY_VISIBLE := "visible"
const _STRATEGY_IDLE := "idle"

const _PLACEHOLDER_GROUP := "island_placeholders"

signal island_mounted(name: String, strategy: String)
signal island_skipped(name: String, reason: String)

## Public entry point. Call this after a scene is fully loaded.
func mount_placeholders(root: Node) -> int:
	if not is_instance_valid(root):
		return 0

	var count := 0
	for placeholder in _find_placeholders(root):
		if not is_instance_valid(placeholder) or placeholder.is_mounted():
			continue
		if placeholder.island_name.is_empty():
			island_skipped.emit("", "empty island_name")
			continue

		var scene := IslandRegistry.resolve(placeholder.island_name)
		if scene == null:
			island_skipped.emit(placeholder.island_name, "not in registry")
			push_warning("[Islands] '%s' not in registry" % placeholder.island_name)
			continue

		match placeholder.load_strategy:
			_STRATEGY_EAGER:
				_mount(placeholder, scene)
			_STRATEGY_VISIBLE:
				_mount_when_visible(placeholder, scene)
			_STRATEGY_IDLE:
				_mount_when_idle(placeholder, scene)
			_:
				island_skipped.emit(placeholder.island_name, "unknown strategy: %s" % placeholder.load_strategy)
				push_warning("[Islands] unknown strategy '%s' for '%s'" % [placeholder.load_strategy, placeholder.island_name])
				continue

		count += 1
	return count


## Pre-load islands whose triggers appear in [param text]. Useful for
## chat commands: when a player types "/trade with Bob", the trade
## island is mounted before the command runs.
func hydrate_for_input(text: String) -> Array[String]:
	var islands := IslandRegistry.islands_triggered_by(text)
	for name in islands:
		# Eager-hydrate: mount immediately regardless of placeholder strategy
		var placeholder := _find_placeholder_by_name(name)
		if placeholder and not placeholder.is_mounted():
			var scene := IslandRegistry.resolve(name)
			if scene:
				_mount(placeholder, scene)
	return islands


# ---------------------------------------------------------------------
# Mount implementations
# ---------------------------------------------------------------------

func _mount(placeholder: Node, scene: PackedScene) -> void:
	if not is_instance_valid(placeholder):
		return
	_replace_with_scene(placeholder, scene)
	island_mounted.emit(placeholder.island_name, _STRATEGY_EAGER)


func _mount_when_visible(placeholder: Node, scene: PackedScene) -> void:
	if not is_instance_valid(placeholder):
		return
	# Defer the check to the next frame so the scene has its final position
	placeholder.visibility_changed.connect(_on_visibility.bind(placeholder, scene), CONNECT_ONE_SHOT)
	# If already visible, force the callback to fire next frame
	if placeholder.visible:
		call_deferred("_on_visibility", placeholder, scene)


func _on_visibility(placeholder: Node, scene: PackedScene) -> void:
	if not is_instance_valid(placeholder) or placeholder.is_mounted():
		return
	if not placeholder.visible:
		return
	_replace_with_scene(placeholder, scene)
	island_mounted.emit(placeholder.island_name, _STRATEGY_VISIBLE)


func _mount_when_idle(placeholder: Node, scene: PackedScene) -> void:
	if not is_instance_valid(placeholder):
		return
	# Godot has no requestIdleCallback, so we approximate with a process_frame
	# listener that waits for a few low-cost frames before mounting.
	var holder := _IdleMountHolder.new()
	holder.placeholder = placeholder
	holder.scene = scene
	holder.manager = self
	holder.frames_remaining = 3
	placeholder.get_tree().root.add_child(holder)


# ---------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------

func _find_placeholders(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	_collect_placeholders(root, out)
	return out


func _collect_placeholders(node: Node, out: Array[Node]) -> void:
	if node.is_in_group(_PLACEHOLDER_GROUP):
		out.append(node)
	for child in node.get_children():
		_collect_placeholders(child, out)


func _find_placeholder_by_name(name: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for placeholder in tree.get_nodes_in_group(_PLACEHOLDER_GROUP):
		if is_instance_valid(placeholder) and placeholder.island_name == name and not placeholder.is_mounted():
			return placeholder
	return null


func _replace_with_scene(placeholder: Node, scene: PackedScene) -> void:
	if placeholder.is_mounted():
		return
	placeholder.mark_mounted()

	var parent := placeholder.get_parent()
	if parent == null:
		return
	var index := placeholder.get_index()

	var instance := scene.instantiate()
	if instance == null:
		push_warning("[Islands] failed to instantiate scene for '%s'" % placeholder.island_name)
		return

	# Inherit position / size / anchor if both are Controls
	if placeholder is Control and instance is Control:
		var p_ctrl := placeholder as Control
		var i_ctrl := instance as Control
		i_ctrl.position = p_ctrl.position
		i_ctrl.size = p_ctrl.size
		i_ctrl.anchor_left = p_ctrl.anchor_left
		i_ctrl.anchor_top = p_ctrl.anchor_top
		i_ctrl.anchor_right = p_ctrl.anchor_right
		i_ctrl.anchor_bottom = p_ctrl.anchor_bottom
		i_ctrl.offset_left = p_ctrl.offset_left
		i_ctrl.offset_top = p_ctrl.offset_top
		i_ctrl.offset_right = p_ctrl.offset_right
		i_ctrl.offset_bottom = p_ctrl.offset_bottom

	parent.remove_child(placeholder)
	parent.add_child(instance)
	parent.move_child(instance, index)
	instance.name = placeholder.island_name
	placeholder.queue_free()


# ---------------------------------------------------------------------
# Idle helper (private)
# ---------------------------------------------------------------------

class _IdleMountHolder extends Node:
	var placeholder: Node
	var scene: PackedScene
	var manager: IslandManager
	var frames_remaining: int = 0

	func _process(_delta: float) -> void:
		if not is_instance_valid(placeholder) or placeholder.is_mounted():
			queue_free()
			return
		frames_remaining -= 1
		if frames_remaining <= 0:
			if is_instance_valid(manager):
				manager._mount(placeholder, scene)
			queue_free()
