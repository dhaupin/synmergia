extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var Sph = load("res://core/frame/math/spherical.gd")
	var seed_b: PackedByteArray = Gen.world_seed_bytes()
	var d_home: Vector3 = Sph.spherical_to_cartesian(0.0, 3.0, 0.0, 1.0)
	var cf: Color = Gen.vertex_color(d_home, seed_b, 10.0, 0.0)
	var cc: Color = Gen.vertex_color(d_home, seed_b, 15.0, 1.0)
	print("forest=", cf, " cliff=", cc)
	print("road=", Gen.road_state_at(d_home, seed_b), " id=", Gen.climate_biome_id(d_home, seed_b), " t=", Gen.climate_temperature(d_home, seed_b))
	quit(0)
