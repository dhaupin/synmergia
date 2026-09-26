## HitboxProfile -- data-driven collision shape per creature archetype
## (hitbox work, batch 6). One profile per body plan so hitboxes are
## authored as data instead of hand-placed inline in every .tscn, and
## so creature hitboxes match what the player actually SEE on screen
## (a wolf is wide and long, a slime is a ball, a boss fills the gate).
##
## Layering (later wins):
##   1. profile .tres base dims
##   2. EnemyData.scale (clamped) -- bosses/elites multiply the base
##      plan so a scale-2.6 colossus hits like one. Visual model scale
##      uses the SAME multiplier, so hitbox always matches the model.
##   3. stance variant (standing/crouch) -- players swap shapes, never
##      scale, when crouching/sliding.
##
## FAIRNESS RULE (species PvP): every PLAYABLE species must resolve to
## the SAME profile id and players never scale their hitbox by species,
## sex, or body_type. Bigger hitbox = eats more hits = worse PvP. The
## naming lint enforces species equality; hitbox_player.tres is the one
## knob that resizes ALL of them together.
##
## .tres files live in data/hitbox_profiles/ and are consumed via
## DataService. Profiles are pure data: no behavior lives here.
extends Resource
class_name HitboxProfile

enum ShapeKind {
	CAPSULE,  # humanoids -- radius + height, slides under obstacles
	BOX,      # beasts -- width x height x depth
	SPHERE    # blobs -- single radius
}

@export var id: String = ""
@export var display_name: String = "Hitbox Profile"

## Which primitive this profile builds.
@export var kind: ShapeKind = ShapeKind.CAPSULE

# -- Standing dims -----------------------------------------------------------
## CAPSULE: radius + total height (cylinder + both caps).
@export var radius: float = 0.4
@export var height: float = 1.8
## BOX: full extents (x = width, y = height, z = length).
@export var size: Vector3 = Vector3(0.8, 1.8, 0.6)
## SPHERE: radius (falls back to `radius` above when zero).
@export var sphere_radius: float = 0.0

## Center offset along +Y from the entity origin. Entity origin is
## FEET-ON-FLOOR everywhere, so this is normally height / 2.
@export var height_offset: float = 0.9

# -- Crouch variant (players only; enemies never stance-swap) ----------------
## 0 height = no crouch variant; stance requests fall back to standing.
@export var crouch_height: float = 0.0
@export var crouch_radius: float = 0.0
@export var crouch_height_offset: float = 0.0

# -- Scale policy ------------------------------------------------------------
## Hitbox scale is CLAMPED to [min_scale, max_scale] after multiplying
## by EnemyData.scale so a data typo cannot produce a 50-meter wolf.
@export var min_scale: float = 0.25
@export var max_scale: float = 4.0

## True when this profile is the locked PvP-fair player hitbox: every
## playable species must reference it and neither species, sex, nor
## body_type may scale it. The naming lint enforces both halves.
@export var pvp_fair: bool = false


func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")


## Clamp a base scale multiplier into the profile's safe band.
func clamp_scale(base_scale: float) -> float:
	return clampf(base_scale, min_scale, max_scale)


## Effective dims for a stance + base scale multiplier, as a Dictionary:
##   kind: int (ShapeKind), radius/height/size/offset all pre-multiplied.
## stance: "standing" | "crouch" (crouch falls back to standing when the
## profile defines no crouch variant).
func get_dims(base_scale: float = 1.0, stance: String = "standing") -> Dictionary:
	var s := clamp_scale(base_scale)
	var use_crouch := stance == "crouch" and crouch_height > 0.0
	var r := crouch_radius if use_crouch and crouch_radius > 0.0 else radius
	var h := crouch_height if use_crouch else height
	var off := crouch_height_offset if use_crouch and crouch_height_offset > 0.0 else height_offset
	var sz: Vector3 = size * s if kind == ShapeKind.BOX else size
	return {
		"kind": kind,
		"radius": r * s,
		"height": h * s,
		"sphere_radius": (sphere_radius if sphere_radius > 0.0 else radius) * s,
		"size": sz,
		"offset": off * s,
	}


## Build a fresh Godot Shape3D for a stance + base scale. Callers own the
## returned shape (assign it to a CollisionShape3D).
func build_shape(base_scale: float = 1.0, stance: String = "standing") -> Shape3D:
	var d := get_dims(base_scale, stance)
	if kind == ShapeKind.BOX:
		var box := BoxShape3D.new()
		box.size = d["size"]
		return box
	if kind == ShapeKind.SPHERE:
		var sp := SphereShape3D.new()
		sp.radius = d["sphere_radius"]
		return sp
	var cap := CapsuleShape3D.new()
	cap.radius = d["radius"]
	cap.height = d["height"]
	return cap
