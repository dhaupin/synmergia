## field2_salt_probe - the decorative/anchored SPLIT receipt (the
## FIELD-2 board item: nature's decorative slice recombines per session,
## the anchored slice never moves). The clipmap's PropLayer owns the law
## now; this drives it directly (pure derive, no boot):
##   1) RECOMBINE: the tuft (decorative) field derived under different
##      session salts produces different instances (the session salt
##      moves the grass),
##   2) DETERMINISM: the SAME salt derives identical instances twice (a
##      session is internally deterministic),
##   3) THE ANCHOR LAW: the DETAIL (harvestable) kinds derive IDENTICALLY
##      under different salts (ore/mooncap/anchor culture stays
##      world-seed pure; the harvest ledger never drifts),
##   4) THE LIVE SALT: the booted layer carries a non-zero day salt.
## Run headless: godot --headless --path . --script res://dev_temp/probes/field2_salt_probe.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const PropLayer = preload("res://core/world/prop_layer.gd")
const Provider = preload("res://scenes/worlds/terrain_provider.gd")

var _globe: Node


func _init() -> void:
	call_deferred("_run")


func _site_key(inst: Dictionary) -> String:
	# The placement fingerprint: a harvestable site's dir + kind (tufts
	# carry no kind, so their dir + scale/yaw is the fingerprint).
	if inst.has("kind"):
		return "%d|%.5f,%.5f,%.5f" % [int(inst["kind"]), inst["dir"].x, inst["dir"].y, inst["dir"].z]
	return "tuft|%.5f,%.5f,%.5f" % [inst["dir"].x, inst["dir"].y, inst["dir"].z]


func _detail_keys(data: Dictionary) -> Array:
	var out: Array = []
	for rec in data.get("instances", []):
		if int(rec.get("family", -1)) == PropLayer.FAMILY_DETAIL:
			out.append(_site_key(rec))
	return out


func _tuft_keys(data: Dictionary) -> Array:
	# Tuft placement shares the anchored detail loop, so the DECORATIVE
	# recombination lives in the blade's appearance (scale + yaw).
	var out: Array = []
	for t in data.get("tufts", []):
		out.append("%.5f,%.5f,%.5f|%.3f|%.3f" % [t["dir"].x, t["dir"].y, t["dir"].z,
			float(t.get("scale", 0.0)), float(t.get("yaw", 0.0))])
	return out


func _run() -> void:
	# Drive the layer directly (pure derive). Pick a homeland chunk.
	var layer = PropLayer.new()
	var parent := Node3D.new()
	get_root().add_child(parent)
	layer.configure(Provider.new(), RADIUS, parent)
	layer.chunk_depth = 6
	var key: int = PropChunk.chunk_for_dir(Provider.new().spawn_dir(), 6)

	# 1) RECOMBINE: two salts -> different tuft instances.
	layer._decor_salt = 100
	var tuft_a: Array = _tuft_keys(layer.derive_fresh(key))
	layer._decor_salt = 200
	var tuft_b: Array = _tuft_keys(layer.derive_fresh(key))
	print("SALT tufts saltA=%d saltB=%d same=%s" % [tuft_a.size(), tuft_b.size(), str(tuft_a == tuft_b)])
	if tuft_a == tuft_b:
		print("SALT-MISS the tuft chain ignored the salt (no recombination)")
		quit(1)
		return

	# 2) DETERMINISM: same salt twice = same field.
	layer._decor_salt = 100
	var tuft_a2: Array = _tuft_keys(layer.derive_fresh(key))
	print("SALT tufts repeat=%s" % str(tuft_a2 == tuft_a))
	if tuft_a2 != tuft_a:
		print("SALT-MISS the decorative chain shifted inside one session")
		quit(1)
		return

	# 3) THE ANCHOR LAW: the detail chain is salt-immune.
	layer._decor_salt = 100
	var det_a: Array = _detail_keys(layer.derive_fresh(key))
	layer._decor_salt = 200
	var det_b: Array = _detail_keys(layer.derive_fresh(key))
	print("SALT detail sites=%d stable=%s" % [det_a.size(), str(det_a == det_b)])
	if det_a != det_b:
		print("SALT-MISS the detail chain moved (the anchor law broke)")
		quit(1)
		return

	# 4) THE LIVE SALT: the booted layer carries a non-zero day salt.
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(10):
		await process_frame
	var streamer = _globe.get("streamer")
	if streamer == null:
		print("SALT-MISS no streamer on the boot")
		quit(1)
		return
	var pl = streamer.prop_layer()
	var live_salt: int = int(pl._decor_salt)
	print("SALT live salt=%d (>0 = the day salt rides the boot)" % live_salt)
	if live_salt <= 0:
		print("SALT-MISS the boot salt did not arm")
		quit(1)
		return
	print("SALT-OK")
	quit(0)
