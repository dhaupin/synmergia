## InstancePropKit -- the instanced-zone prop law (labs/prd-clipmap.md 11a).
##
## Instanced rooms (arena / coliseum / sandpit / dungeon) do NOT boot a globe,
## so they cannot ride PropLayer's globe-addressed chunks. This kit is the
## local-frame sibling: a deterministic, seed-derived, mode-aware scatter of
## NON-COLLIDING decoration over the room's flat floor. It reuses the SAME
## SeedChain law the globe props use (a room is a pure function of its seed),
## so a room reads as a slice of its biome instead of a bare box.
##
## Fairness law: decoration NEVER lands in the bout center (keep-out radius)
## or within a lane of a team spawn point, and it never collides -- the solid
## cover stays the arena's own `_build_cover` (the fair, symmetric layout).
## This kit is decoration only; it changes the LOOK, never the fight.
extends RefCounted

const SeedChain = preload("res://core/frame/kv/seed_chain.gd")

## One shared material cache per kit instance (rooms are short-lived).
var _mats: Dictionary = {}


## Scatter decoration over a room of half-extent `half`. `palette` carries the
## mode colors (tuft/bush/stone), `keep_clear` are the points (team spawns +
## solid cover) decoration must not crowd. Returns the number of props placed.
func build(parent: Node3D, half: float, mode: int, salt: int, palette: Dictionary,
		keep_clear: Array) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_int("instances/props/%d/%d" % [mode, salt])
	var keep_in: float = 0.35 * half      # the bout center stays clean
	var band: float = 0.95 * half         # props never touch the wall
	var candidates: int = maxi(12, int(half * 0.9))
	var placed: int = 0
	for _i in range(candidates):
		var ang: float = rng.randf_range(0.0, TAU)
		var rad: float = rng.randf_range(keep_in, band)
		var pos := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		if _near_keep_clear(pos, keep_clear):
			continue
		_build_one(parent, pos, rng, mode, palette)
		placed += 1
	return placed


func _build_one(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, mode: int,
		palette: Dictionary) -> void:
	var kind: int = _pick_kind(rng, mode)
	var g := Node3D.new()
	g.name = "RoomProp%d" % parent.get_child_count()
	g.position = pos
	g.rotation.y = rng.randf_range(0.0, TAU)
	match kind:
		0:  # tuft: a low grass cluster (three blades)
			var blade_mat := _mat("tuft", palette.get("tuft", Color(0.34, 0.44, 0.22)))
			for b in range(3):
				var blade := MeshInstance3D.new()
				blade.mesh = _cyl(0.02, 0.07, rng.randf_range(0.22, 0.40))
				blade.material_override = blade_mat
				blade.position = Vector3(rng.randf_range(-0.12, 0.12), 0.18, rng.randf_range(-0.12, 0.12))
				blade.rotation.z = rng.randf_range(-0.18, 0.18)
				g.add_child(blade)
		1:  # bush: a low rounded shrub
			var bush := MeshInstance3D.new()
			var r: float = rng.randf_range(0.35, 0.65)
			bush.mesh = _sphere(r, 0.7)
			bush.material_override = _mat("bush", palette.get("bush", Color(0.28, 0.38, 0.20)))
			bush.position = Vector3(0.0, r * 0.5, 0.0)
			g.add_child(bush)
		_:  # stone: a small half-buried pebble (decoration, never solid)
			var stone := MeshInstance3D.new()
			var sr: float = rng.randf_range(0.18, 0.42)
			stone.mesh = _sphere(sr, 0.55)
			stone.material_override = _mat("stone", palette.get("stone", Color(0.45, 0.43, 0.40)))
			stone.position = Vector3(0.0, sr * 0.30, 0.0)
			g.add_child(stone)
	parent.add_child(g)


## Per-mode kit: how often each kind appears. Desert coliseums lean on dry
## tufts + stones; the olive sandpit grows bushes; rust badlands get stones.
func _pick_kind(rng: RandomNumberGenerator, mode: int) -> int:
	var roll: float = rng.randf()
	match mode:
		0:  # ELIMINATION (coliseum): tuft 60 / stone 30 / bush 10
			return 0 if roll < 0.60 else (2 if roll < 0.90 else 1)
		2:  # ROYALE (Sundered Valley): stone 55 / tuft 35 / bush 10
			return 2 if roll < 0.55 else (0 if roll < 0.90 else 1)
		_:  # TEAM_DEATHMATCH (sandpit): bush 45 / tuft 40 / stone 15
			return 1 if roll < 0.45 else (0 if roll < 0.85 else 2)


func _near_keep_clear(pos: Vector3, keep_clear: Array) -> bool:
	for sp in keep_clear:
		if pos.distance_to(Vector3(sp.x, 0.0, sp.z)) < 5.0:
			return true
	return false


func _seed_int(path: String) -> int:
	var bytes: PackedByteArray = SeedChain.derive_seed([], path)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 131 + b) % 9007199254740991
	return acc


func _mat(key: String, color: Color) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _cyl(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = 5
	m.rings = 1
	m.cap_top = false
	return m


func _sphere(r: float, aspect: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 * aspect
	m.radial_segments = 8
	m.rings = 4
	return m
