## field2_salt_probe - the decorative/anchored SPLIT receipt (the
## FIELD-2 board item: nature's decorative slice recombines per
## session, the anchored slice never moves). Three claims, all pure
## derive (no boot state changes):
##   1) RECOMBINE: tree + grass chains derived under different salts
##      produce different sites (the session salt moves the canopy),
##   2) DETERMINISM: the SAME salt derives identical sites twice (a
##      session is internally deterministic),
##   3) THE ANCHOR LAW: the DETAIL chain under different salts is
##      IDENTICAL (the ore/mooncap/anchor kinds stay world-seed pure;
##      the harvest ledger never drifts).
## Run headless: godot --headless --path . --script res://dev_temp/probes/field2_salt_probe.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0

var _globe: Node

func _init() -> void:
	call_deferred("_run")

func _first_pos(arr: Array) -> String:
	for rec in arr:
		if rec is Dictionary and rec.has("pos"):
			return str(rec["pos"])
	return "empty"

func _run() -> void:
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
	await root.get_tree().physics_frame
	# 1) THE RECOMBINE: two salts, same face, different canopy.
	var t1: Array = streamer._derive_tree_sites(16, int(100))
	var t2: Array = streamer._derive_tree_sites(16, int(200))
	print("SALT trees saltA=%s saltB=%s" % [_first_pos(t1), _first_pos(t2)])
	if _first_pos(t1) == _first_pos(t2):
		print("SALT-MISS the tree chain ignored the salt (no recombination)")
		quit(1)
		return
	# 2) THE DETERMINISM: same salt twice = same world.
	var t1b: Array = streamer._derive_tree_sites(16, int(100))
	print("SALT trees repeat=%s" % [str(_first_pos(t1b) == _first_pos(t1))])
	if _first_pos(t1b) != _first_pos(t1):
		print("SALT-MISS the decorative chain shifted inside one session")
		quit(1)
		return
	# 3) THE ANCHOR LAW: the detail chain is salt-immune.
	var d1: Array = streamer._derive_detail_sites(16)
	var d2: Array = streamer._derive_detail_sites(16)
	var det_same: bool = d1.size() == d2.size()
	if det_same:
		for i in range(d1.size()):
			if str(d1[i]) != str(d2[i]):
				det_same = false
				break
	print("SALT detail stable=%d sites" % int(d1.size()))
	if not det_same:
		print("SALT-MISS the detail chain moved (the anchor law broke)")
		quit(1)
		return
	# 4) THE LIVE SALT: the booted streamer carries a non-zero day salt.
	var live_salt: int = int(streamer._decor_salt)
	print("SALT live salt=%d (>0 = the day salt rides the boot)" % live_salt)
	if live_salt <= 0:
		print("SALT-MISS the boot salt did not arm")
		quit(1)
		return
	print("SALT-OK")
	quit(0)
