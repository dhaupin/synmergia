## LayerProfile -- named collision bits as data (round 10).
## The repo had ~50 hand-written magic-bit sites (0b0000111, 0xFFFF...)
## across 14 files; a bit drift in one of them silently changes who
## collides with whom. One .tres (data/physics_layers/) maps semantic
## names to Godot collision bits so sites read
## Layers.layer_bit("entity") instead of 0b0000001.
##
## .tres files live in data/physics_layers/ and are consumed via
## DataService (same path as HitboxProfile/MovementProfile). Pure
## data: no behavior lives here. The bit VALUES are the de-facto map
## the codebase already uses (audit 2026-10-02) -- changing them is a
## physics-behavior change and must be deliberate:
##   bit 1 (value 1) entity/player -- players, enemies, NPCs, targets
##   bit 2 (value 2) solid -- PropCollider props, walls, features
##   bit 3 (value 4) ground -- floors, terrain, the surface pad
## Bits 4+ are RESERVED (unused today). The legacy broad masks
## (0b0111111, 0b1111110, 0xFFFFFFFF) keep their exact values via
## group "value" overrides -- behavior stays byte-identical.
extends Resource
class_name LayerProfile

## Every bit this profile declares, as ordered Dictionaries:
##   [{name: "entity", bit: 1, description: "..."}, ...]
@export var bits: Array = []

## Named groups callers build masks from (compound masks are data too,
## not new magic arithmetic at the call site):
##   {name: "world", bits: "entity,solid,ground"}     -- composed
##   {name: "everything", value: 4294967295}          -- explicit
## A "value" override wins over "bits" (used for the legacy broad
## masks that span reserved bits -- exact old values, no drift).
@export var groups: Array = []

@export var id: String = ""
@export var display_name: String = "Physics Layers"

## True when the declared bits already match the de-facto audit map
## (entity=1, solid=2, ground=4). Guards against accidental renumbering
## by data edit: code that bootstraps from this file asserts it.
@export var audit_locked: bool = true


func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")


## Bit VALUE (1, 2, 4, ...) for a named layer, or 0 when unknown
## (loud in debug -- a typo must never silently produce an empty mask).
func bit(layer_name: String) -> int:
	for b in bits:
		if b is Dictionary and str(b.get("name", "")) == layer_name:
			return int(b.get("bit", 0))
	push_warning("LayerProfile '%s': unknown layer name '%s'" % [id, layer_name])
	return 0


## Mask for a named GROUP ("world" -> entity|solid|ground), or 0.
## Groups may compose named bits ("bits") or declare an explicit
## "value" (legacy broad masks) -- value wins when both are present.
func mask(group_name: String) -> int:
	for g in groups:
		if g is Dictionary and str(g.get("name", "")) == group_name:
			if g.has("value"):
				return int(g.get("value", 0))
			var m: int = 0
			for part in str(g.get("bits", "")).split(","):
				m = m | bit(part.strip_edges())
			return m
	push_warning("LayerProfile '%s': unknown group name '%s'" % [id, group_name])
	return 0


# -- Static access (script-mode tests mount no autoloads) -------------------

static var _static_profile: LayerProfile = null


## Resolve the physics_layers_main profile via DataService when mounted,
## falling back to the baked audit map so deep script-mode still works.
static func get_profile() -> LayerProfile:
	if _static_profile != null:
		return _static_profile
	var ml := Engine.get_main_loop()
	if ml != null and ml is SceneTree:
		var ds = (ml as SceneTree).root.get_node_or_null("DataService")
		if ds != null and ds.has_method("get_layer_profile"):
			var p = ds.call("get_layer_profile", "physics_layers_main")
			if p != null:
				_static_profile = p
				return p
	_static_profile = _default_profile()
	return _static_profile


## The audit map as a fallback profile (identical values to the .tres).
## Test/diagnostic seam: keeps headless probes running when autoloads
## are not mounted, with the same values data declares.
static func _default_profile() -> LayerProfile:
	# Static-factory new(): bare self-construction, valid in static
	# funcs and independent of the global class registry (deep
	# script-mode probes load this file without a fresh class cache).
	var p := new()
	p.id = "physics_layers_main"
	p.display_name = "Physics Layers (baked audit map)"
	p.bits = [
		{"name": "entity", "bit": 1},
		{"name": "solid", "bit": 2},
		{"name": "ground", "bit": 4},
	]
	p.groups = [
		{"name": "world", "bits": "entity,solid,ground"},
		{"name": "entity_solid", "bits": "entity,solid"},
		{"name": "solid_ground", "bits": "solid,ground"},
		{"name": "all_solid", "value": 63},
		{"name": "geometry_no_entity", "value": 126},
		{"name": "everything", "value": 4294967295},
	]
	return p


## Named-bit conveniences (the only API call sites should use).
## Named layer_bit/group_mask (not bit/mask) so the statics never
## shadow the instance methods of the same name.
##   Layers.layer_bit("entity"), Layers.group_mask("world")
static func layer_bit(layer_name: String) -> int:
	return get_profile().bit(layer_name)


static func group_mask(group_name: String) -> int:
	return get_profile().mask(group_name)
