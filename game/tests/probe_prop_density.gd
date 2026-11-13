## probe_prop_density - the visibility audit for the player report
## "I haven't seen trees or rocks on the starter plains."
## Boots the globe at the planet scale and answers the two candidate
## causes separately:
##   1) CHUNK CENSUS: how many props DO the PropLayer's built chunks
##      carry, and what are the nearest ones to the boot (GROUND DISTANCE)?
##   2) BAND CENSUS: how many props land in cumulative arcs
##      (<=0.03, <=0.06, <=0.12, <=0.25 rad around the boot)?
## If chunks carry props but every band is empty, the scatter DENSITY
## is the gap; if chunks are empty near the boot, placement is.
##
## This is a CENSUS diagnostic (no assertions). The clipmap's PropLayer
## is the sole flora path now (chunks named "PropChunk_%d").
## Run headless:   godot --headless --path . --script res://tests/probe_prop_density.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const RADIUS := 20000.0
const BANDS := [0.03, 0.06, 0.12, 0.25]

var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _kind_of(base: String) -> String:
	if base.begins_with("Boulder"):
		return "boulder"
	if base.begins_with("Rock"):
		return "rock"
	if base.begins_with("Tree"):
		return "tree"
	return "detail"


func _looks_detail(base: String) -> bool:
	for pre in ["Cattail", "Ore", "Bush", "Tuft", "Flower", "Reed", "Detail", "Shell", "Wrack"]:
		if base.begins_with(pre):
			return true
	return false


func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	var t0 := Time.get_ticks_msec()
	print("BOOT_MS_instantiate=", Time.get_ticks_msec() - t0)
	for _i in range(6):
		await process_frame
	print("BOOT_MS_after6frames=", Time.get_ticks_msec() - t0)
	for _i in range(90):
		await root.get_tree().physics_frame
		if _i % 10 == 9:
			print("BOOT_MS_after", _i + 1, "physics=", Time.get_ticks_msec() - t0)
	# The flora derives on worker threads; the census waits for the pending
	# derive jobs to drain (bounded) before counting.
	var waited := 0
	while _globe.get("clipmap").pending_derive() > 0 and waited < 1200:
		await root.get_tree().physics_frame
		waited += 1
	print("PENDING_DRAINED_after=", waited + 90, " frames, tmsec=", Time.get_ticks_msec() - t0)

	var clipmap = _globe.get("clipmap")
	var player = _globe.get("player")
	var planet_center: Vector3 = _globe.get("planet_center")
	var radius_pl: float = _globe.get("planet_radius")
	var pdir: Vector3 = (player.global_position - planet_center).normalized()
	var pl = clipmap.prop_layer()

	var band_counts: Dictionary = {}
	for b in BANDS:
		band_counts[b] = {"rock": 0, "boulder": 0, "tree": 0, "detail": 0}
	var total := {"rock": 0, "boulder": 0, "tree": 0, "detail": 0}
	var chunks_empty := 0
	var nearest: Array = []  # [ground_m, kind]
	var chunk_report: Array = []

	if pl != null:
		for k in pl._built.keys():
			var chunk = pl._built.get(k)
			if chunk == null or not is_instance_valid(chunk):
				continue
			var per := {"rock": 0, "boulder": 0, "tree": 0, "detail": 0}
			if chunk.get_child_count() == 0:
				chunks_empty += 1
				chunk_report.append("chunk=%d EMPTY" % k)
				continue
			var name_samples: Array = []
			for ch in chunk.get_children():
				if ch is CollisionObject3D or not (ch is Node3D):
					continue
				var cname := String(ch.name)
				# The tuft field: one MultiMesh per chunk -- the blade mass
				# is its instance_count (count as detail).
				if cname == "Tufts":
					var tmm = ch.get("multimesh")
					if tmm != null:
						per["detail"] = int(per["detail"]) + int(tmm.instance_count)
						total["detail"] = int(total["detail"]) + int(tmm.instance_count)
					continue
				if name_samples.size() < 10:
					name_samples.append(cname)
				var kind := _kind_of(cname)
				if kind == "detail" and not _looks_detail(cname):
					continue
				per[kind] = int(per[kind]) + 1
				total[kind] = int(total[kind]) + 1
				var pw: Vector3 = (ch.global_position - planet_center).normalized()
				var ang: float = pw.angle_to(pdir)
				var ground_m: float = ang * radius_pl
				nearest.append([ground_m, kind])
				for b in BANDS:
					if ang <= float(b):
						band_counts[b][kind] = int(band_counts[b][kind]) + 1
						break
			chunk_report.append("chunk=%d %s names=%s" % [k, str(per), str(name_samples)])

	print("player r-planet=", (player.global_position - planet_center).length() - radius_pl,
		" BUILT_CHUNKS=", pl.built_count() if pl != null else 0)
	for line in chunk_report:
		print("  ", line)
	print("TOTALS=", str(total), " EMPTY_CHUNKS=", chunks_empty)
	nearest.sort_custom(func(a, b): return a[0] < b[0])
	for i in range(mini(12, nearest.size())):
		print("  NEAREST %02d: ground=%6.0f m kind=%s" % [i, nearest[i][0], nearest[i][1]])
	for b in BANDS:
		var bc: Dictionary = band_counts[b]
		print("BAND <=%4.2f rad (%5.0f m): rock=%d boulder=%d tree=%d detail=%d" %
			[float(b), float(b) * radius_pl, bc["rock"], bc["boulder"], bc["tree"], bc["detail"]])
	quit(0)
