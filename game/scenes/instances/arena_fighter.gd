# ArenaFighter - planar-gravity body for instanced arenas.
#
# Companion to arena_instance.gd (S10). Unlike the globe path (radial
# gravity in globe_player.gd), instanced worlds are PLANAR by contract:
# straight-down gravity at InstanceContract.GRAVITY_FORCE with UP = +Y
# (locked decision 3; radial gravity never reaches instances). This
# body is deliberately dumb: the bout controller (arena_instance.gd)
# owns scoring, elimination, and shields; this script only falls,
# stands, and reports its state.
#
# No class_name (never instantiated by type elsewhere; the instance
# scene preloads this file). Built entirely in code like globe_player.
extends CharacterBody3D

const Contract = preload("res://core/schemas/instance_contract.gd")

var fighter_id: String = ""
var team: int = 0
var alive: bool = true
## Trial-bout filler (marshal's dummies): reduced combat presence --
## a new player's first fight must be winnable. Zero = full health.
var trial_health: int = 0
# Spawn-shield deadline (unix seconds). While now < shielded_until the
# controller rejects the fighter's death (TEAM_DEATHMATCH protection).
var shielded_until: float = 0.0
# Contract gravity force; straight down, set once at ready.
var gravity_force: float = Contract.GRAVITY_FORCE

var _mesh: MeshInstance3D

func _ready() -> void:
	gravity_force = Contract.GRAVITY_FORCE
	up_direction = Vector3.UP
	_build_visual()

func setup(id: String, team_id: int, trial: bool = false) -> void:
	fighter_id = id
	team = team_id
	if trial:
		trial_health = 45

func _physics_process(delta: float) -> void:
	if not alive:
		return
	# Planar contract gravity: -Y at the shared force, never radial.
	velocity.y -= gravity_force * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = 0.0

## Apply the spawn shield (TEAM_DEATHMATCH respawns). Seconds from the
## zone's bout rules; the controller decides when this is granted.
func apply_spawn_shield(seconds: float) -> void:
	shielded_until = Time.get_unix_time_from_system() + seconds

func is_shielded() -> bool:
	return Time.get_unix_time_from_system() < shielded_until

## Fire-and-you-lose-it rule (owner decision, S11 goals): any
## SELF-INITIATED combat action breaks the spawn shield immediately --
## attacking, casting a skill, using a potion, or applying a self-buff.
## The combat bridge calls this when the actor initiates. Effects the
## fighter RECEIVES (team aura, aoe heal, buff from another player)
## never call this: you cannot lose protection for something you did
## not choose to do.
func break_shield() -> void:
	shielded_until = 0.0

## Elimination: one life gone. Kills motion and collision; the mesh
## drops to grey so a rendered probe can see the state.
func eliminate() -> void:
	alive = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if _mesh != null:
		_set_tint(Color(0.4, 0.4, 0.4))

## Revive at a position (TEAM_DEATHMATCH respawn). Restores collision,
## re-arms the body, and re-applies the shield.
func respawn_at(pos: Vector3, shield_seconds: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	alive = true
	collision_layer = 1
	collision_mask = 1
	apply_spawn_shield(shield_seconds)
	_set_tint(_team_color(team))

## Effective combat presence for this fighter (trial dummies scale
## down; real fighters are full). The combat bridge reads this when
## resolving damage-to-death for entity-less fighters.
func effective_health() -> int:
	return trial_health if trial_health > 0 else 100

func _build_visual() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 2.0
	cap.radius = 0.4
	col.shape = cap
	col.position = Vector3(0, 1, 0)
	add_child(col)

	_mesh = MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.height = 2.0
	cap_mesh.radius = 0.4
	_mesh.mesh = cap_mesh
	_mesh.position = Vector3(0, 1, 0)
	_set_tint(_team_color(team))
	add_child(_mesh)

func _set_tint(c: Color) -> void:
	if _mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	_mesh.material_override = mat

func _team_color(team_id: int) -> Color:
	# Team 0 = blue side, team 1 = red side (ASCII palette).
	if team_id == 0:
		return Color(0.25, 0.45, 0.85)
	return Color(0.85, 0.3, 0.25)
