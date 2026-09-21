## StateBase - Clean base class for state machine states (no class_name to avoid autoload conflicts)
## Replaces the deprecated State class. Used by player controller states.
extends Node

var state_machine: Node = null

func enter(_data: Dictionary = {}) -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass


## Helper: route a transition through the owning state machine.
## Subclasses call this unqualified; it forwards to state_machine.
func transition_to(state_name: String, data: Dictionary = {}) -> void:
	if state_machine and state_machine.has_method("transition_to"):
		state_machine.transition_to(state_name, data)


## Helper: play an animation on the parent's AnimationPlayer if present.
## If the parent has no AnimationPlayer, the call is a no-op. Missing
## animation names fall back to a movement-appropriate clip (slide ->
## crouch -> run, crouch -> idle) so placeholder meshes with only the
## base clips still animate instead of locking into the last pose.
func animation_play(anim_name: String) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var anim: Object = parent.get("animation_player")
	if anim == null:
		anim = parent.get_node_or_null("AnimationPlayer")
	if anim and anim.has_method("has_animation") and anim.has_method("play"):
		if not anim.has_animation(anim_name):
			anim_name = _fallback_animation(anim_name)
		if anim.has_animation(anim_name):
			anim.play(anim_name)

## Movement-family fallbacks for scenes without bespoke clips.
func _fallback_animation(missing: String) -> String:
	match missing:
		"slide":
			return "crouch" if _has_anim("crouch") else ("run" if _has_anim("run") else missing)
		"crouch":
			return "run" if _has_anim("run") else missing
		"run":
			return "idle" if _has_anim("idle") else missing
		_:
			return missing

func _has_anim(anim_name: String) -> bool:
	var anim: Object = get_parent().get("animation_player")
	if anim == null:
		anim = get_parent().get_node_or_null("AnimationPlayer")
	return anim != null and anim.has_method("has_animation") and anim.has_animation(anim_name)