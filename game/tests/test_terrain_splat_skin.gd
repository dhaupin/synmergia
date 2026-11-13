## Terrain skin spike receipt (the texture round, Buffy)
## THE SPIKE ROUND's pins: five tileable procedural skins + the splat
## shader + the splat_skin law exports. The HONEST LEDGER is the law's
## own header: the color law is byte-untouched; the micro-tones (tuft
## sparkle, macro polish, tint wobble, crag strata/fracture dimming)
## stay COLOR-lane only -- the skins carry their own grain. Quixel
## scans slot into the same five texture slots when claimed.
extends SceneTree

var _ok := true
var _pass_count := 0


func _init() -> void:
	# THE LAW TOGGLE
	_ok = _check("gen law: SPLAT_SKIN toggle is law", _gen().SPLAT_SKIN)
	# THE SPLAT EXPORT (probed 2026-11-05: spawn reads GRASSLAND flat,
	# the spawn apron stays dry-green-pured, its steep faces rock).
	var spawn: Vector3 = _gen().SPAWN_CENTER.normalized()
	var seed_b: PackedByteArray = _gen().world_seed_bytes()
	var skin_d: Dictionary = _gen().splat_skin(spawn, seed_b, 10.0, 0.0)
	var splat: Color = skin_d["splat"]
	_ok = _check("splat_skin: spawn apron reads grass-dominant", splat.r > 0.6)
	_ok = _check("splat_skin: spawn apron snow-free (the dry boot law)", skin_d["aux"].x < 0.01)
	_ok = _check("splat_skin: full light (no dim leg at spawn)", skin_d["aux"].y > 0.99)
	_ok = _check("splat_skin: weights bounded in [0,1]",
		splat.r >= 0.0 and splat.r <= 1.0 and splat.g >= 0.0 and splat.g <= 1.0
		and splat.b >= 0.0 and splat.b <= 1.0 and splat.a >= 0.0 and splat.a <= 1.0)
	var skin_d2: Dictionary = _gen().splat_skin(spawn, seed_b, 10.0, 0.0)
	_ok = _check("splat_skin: deterministic (same input = same weights)",
		splat == skin_d2["splat"] and skin_d["aux"] == skin_d2["aux"])
	var steep_d: Dictionary = _gen().splat_skin(spawn, seed_b, 10.0, 0.9)
	_ok = _check("splat_skin: steep faces rock the weight", steep_d["splat"].b > 0.6)
	# The antipode of spawn is open ocean (probed 2026-11-05: its flat
	# reads pure sand): the bed sand skin + the dim wet law leg.
	var sea_d: Dictionary = _gen().splat_skin((-spawn).normalized(), seed_b, -40.0, 0.0)
	_ok = _check("splat_skin: the ocean bed reads sand", sea_d["splat"].a > 0.99)
	_ok = _check("splat_skin: under-shell faces dim (the wet law leg)", sea_d["aux"].y < 0.6)
	# THE CLIPMAP consults (text pins) -- the skin lane is the renderer's, the
	# splat derivation the provider's (the streamer's twin, retired).
	var src := FileAccess.open("res://scenes/worlds/globe_clipmap.gd", FileAccess.READ).get_as_text()
	_ok = _check("clipmap: the skin lane reads the provider surface sample", src.contains("provider.surface_sample(dir)"))
	_ok = _check("clipmap: UV2 carries the aux channel", src.contains('st.set_uv2(v["aux"])'))
	_ok = _check("clipmap: the ring/cap mounts the splat shader material", src.contains("_skin_mat.shader = _skin_shader"))
	var prov_src := FileAccess.open("res://scenes/worlds/terrain_provider.gd", FileAccess.READ).get_as_text()
	_ok = _check("provider: the skin lane derives through TerrainGen.splat_skin_from", prov_src.contains("TerrainGen.splat_skin_from"))
	# THE FIVE SKINS exist and the shader samples all five.
	var tex_dir := "res://assets/textures/terrain/"
	for t in ["grass", "dirt", "rock", "sand", "snow"]:
		var tex: Texture2D = load(tex_dir + t + ".png")
		_ok = _check("skin '%s' loads at 256px" % t, tex != null and tex.get_size() == Vector2(256, 256))
	var shader_src := FileAccess.open("res://assets/shaders/terrain_splat.gdshader", FileAccess.READ).get_as_text()
	for t in ["tex_grass", "tex_dirt", "tex_rock", "tex_sand", "tex_snow"]:
		_ok = _check("shader samples '%s'" % t, shader_src.contains(t))
	_ok = _check("shader does not re-decide biomes (weights only from COLOR/UV2)",
		shader_src.contains("vec4 w = COLOR;") and shader_src.contains("UV2.x") and shader_src.contains("UV2.y"))
	_ok = _check("shader reads steep from the model-space vertex normal", shader_src.contains("v_steep = clamp(1.0 - NORMAL.y"))
	print("")
	print("=== TERRAIN SKIN SPIKE: %d checks, %s ===" % [_pass_count, "ALL GREEN" if _ok else "FAILURES ABOVE"])
	quit(0 if _ok else 1)


func _check(what: String, cond: bool) -> bool:
	if cond:
		_pass_count += 1
		print("PASSED: %s" % what)
	else:
		_ok = false
		print("FAILED: %s" % what)
	return cond


func _gen() -> GDScript:
	return load("res://scenes/worlds/terrain_gen.gd")
