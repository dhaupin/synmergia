## Dodge State - Quick evasive roll with i-frames
extends State

const State = preload("res://scripts/state.gd")
class_name DodgeState

const DURATION: float = 0.3  # Roll duration
const IFRAMES_START: float = 0.05  # I-frames start immediately
const IFRAMES_END: float = 0.25  # I-frames end before animation ends

var elapsed: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO
var has_i_frames: bool = false

func enter(_data: Dictionary = {}) -> void:
	elapsed = 0.0
	has_i_frames = false
	
	var parent := state_machine.get_parent()
	
	# Calculate dodge direction (movement direction or forward if stationary)
	var move_dir := parent.get_movement_direction()
	if move_dir.length() > 0.1:
		dodge_direction = move_dir
	else:
		dodge_direction = -parent.global_transform.basis.z
	
	dodge_direction.y = 0
	dodge_direction = dodge_direction.normalized()
	
	# Apply dodge velocity
	parent.velocity = dodge_direction * parent.dodge_force
	parent.velocity.y = parent.jump_force * 0.3  # Small hop
	
	# Play animation
	animation_play("dodge")

func exit() -> void:
	var parent := state_machine.get_parent()
	parent.is_invincible = false
	has_i_frames = false

func update(delta: float) -> void:
	elapsed += delta
	
	# Update i-frames
	var parent := state_machine.get_parent()
	has_i_frames = elapsed >= IFRAMES_START and elapsed <= IFRAMES_END
	parent.is_invincible = has_i_frames
	
	# Check for early landing
	if parent.is_on_floor() and elapsed > 0.15:
		transition_to("Land")

func physics_update(delta: float) -> void:
	var parent := state_machine.get_parent()
	
	# Slow down during dodge
	var t := elapsed / DURATION
	var friction := 1.0 - smoothstep(0.0, 1.0, t)
	
	parent.velocity.x = dodge_direction.x * parent.dodge_force * friction
	parent.velocity.z = dodge_direction.z * parent.dodge_force * friction
	
	# Continue upward momentum then fall
	if elapsed > 0.1:
		parent.velocity.y = lerp(parent.velocity.y, -10.0, delta * 5)
	
	# Check if dodge is complete
	if elapsed >= DURATION:
		if parent.is_on_floor():
			transition_to("Idle")
		else:
			transition_to("Jump")

func animation_play(anim_name: String) -> void:
	var parent := state_machine.get_parent()
	if parent.animation_player.has_animation(anim_name):
		parent.animation_player.play(anim_name)

func smoothstep(from: float, to: float, weight: float) -> float:
	return lerp(from, to, weight * weight * (3.0 - 2.0 * weight))
