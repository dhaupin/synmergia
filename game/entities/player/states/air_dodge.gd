## AirDodge State - Mid-air dodge with i-frames
extends State

const State = preload("res://core/state/state.gd")
class_name AirDodgeState

const DURATION: float = 0.35  # Longer than ground dodge
const IFRAMES_START: float = 0.0  # Immediate i-frames
const IFRAMES_END: float = 0.3

var elapsed: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO

func enter(_data: Dictionary = {}) -> void:
	elapsed = 0.0

	var parent := state_machine.get_parent()

	# Calculate dodge direction
	var move_dir := parent.get_movement_direction()
	if move_dir.length() > 0.1:
		dodge_direction = move_dir
	else:
		dodge_direction = -parent.global_transform.basis.z

	dodge_direction.y = 0
	dodge_direction = dodge_direction.normalized()

	# Apply dodge velocity (stronger than ground dodge)
	parent.velocity = dodge_direction * parent.air_dodge_force
	parent.velocity.y = parent.jump_force * 0.2  # Small pop

	# Play animation
	animation_play("air_dodge")

func exit() -> void:
	var parent := state_machine.get_parent()
	parent.is_invincible = false

func update(delta: float) -> void:
	elapsed += delta

	var parent := state_machine.get_parent()

	# I-frames active
	parent.is_invincible = elapsed >= IFRAMES_START and elapsed <= IFRAMES_END

	# Allow second dodge if first completes
	if elapsed >= DURATION:
		if parent.is_on_floor():
			transition_to("Land")
		else:
			transition_to("Fall")

func physics_update(delta: float) -> void:
	var parent := state_machine.get_parent()

	# Strong initial burst, then slow
	var t := elapsed / DURATION
	var friction := 1.0 - smoothstep(0.0, 1.0, t)

	parent.velocity.x = dodge_direction.x * parent.air_dodge_force * friction
	parent.velocity.z = dodge_direction.z * parent.air_dodge_force * friction

	# Gravity pulls down after initial burst
	if elapsed > 0.15:
		parent.velocity.y = lerp(parent.velocity.y, -5.0, delta * 3)

func animation_play(anim_name: String) -> void:
	var parent := state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)

func smoothstep(from: float, to: float, weight: float) -> float:
	return lerp(from, to, weight * weight * (3.0 - 2.0 * weight))
