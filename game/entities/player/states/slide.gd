## Slide State - COD Mobile-style slide: sprint momentum into a fast
## crouched slide. Enters from Run while sprinting (dodge input), keeps
## the sprint momentum with heavy friction, exits to Crouch (still
## holding) or Idle when the slide finishes. Heading is locked for the
## slide duration so the player can steer the camera without curving
## the slide itself.
extends "res://core/state/state_base.gd"
class_name SlideState

const SLIDE_DURATION: float = 0.75
const SLIDE_FRICTION: float = 2.6   # exponential velocity decay per second
const MIN_SLIDE_SPEED: float = 3.0
const END_SPEED: float = 2.2        # exit speed -> idle threshold

var _slide_timer: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_speed: float = 0.0

func enter(_data: Dictionary = {}) -> void:
	var parent: PlayerController = state_machine.get_parent()
	_slide_timer = 0.0
	_slide_dir = parent.get_movement_direction()
	if _slide_dir.length() < 0.1:
		_slide_dir = -parent.global_transform.basis.z
		_slide_dir.y = 0.0
		_slide_dir = _slide_dir.normalized() if _slide_dir.length() > 0.01 else Vector3.ZERO
	_slide_speed = maxf(parent.move_speed * 1.9, parent.get_real_velocity().length())
	parent.is_sliding = true
	parent.is_sprinting = false
	animation_play("slide")

func exit() -> void:
	var parent: PlayerController = state_machine.get_parent()
	parent.is_sliding = false

func update(_delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()

	# Jump out of a slide keeps the momentum (COD-style slide jump).
	if Input.is_action_just_pressed("jump") and parent.is_on_floor():
		transition_to("Jump")
		return

	if _slide_timer >= SLIDE_DURATION or _slide_speed < MIN_SLIDE_SPEED:
		_finish_slide()
		return

	# Let the player cancel into attack while sliding.
	if Input.is_action_just_pressed("attack"):
		transition_to("Attack")
		return

func physics_update(delta: float) -> void:
	var parent: PlayerController = state_machine.get_parent()
	if parent == null:
		return
	if not parent.is_on_floor():
		transition_to("Fall")
		return

	_slide_timer += delta
	_slide_speed = _slide_speed / (1.0 + SLIDE_FRICTION * delta)
	var vel: Vector3 = _slide_dir * _slide_speed
	parent.velocity.x = vel.x
	parent.velocity.z = vel.z

	if _slide_speed < END_SPEED and _slide_timer > 0.2:
		_finish_slide()

func _finish_slide() -> void:
	if Input.is_action_pressed("dodge"):
		transition_to("Crouch")
	else:
		transition_to("Idle")
