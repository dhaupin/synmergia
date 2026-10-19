## probe_prop_density - the visibility audit for the player report
## "I haven't seen trees or rocks on the starter plains."
## Boots the streamed globe at the planet scale and answers the two
## candidate causes separately:
##   1) HOLDER CENSUS: how many props DO the live faces carry, and what
##      are the nearest ones to the boot (GROUND DISTANCE)?
##   2) BAND CENSUS: how many props land in cumulative arcs
##      (<=0.03, <=0.06, <=0.12, <=0.25 rad around the boot)?
## If holders carry props but every band is empty, the scatter DENSITY
## is the gap; if holders are empty near the boot, placement is.
## Run headless:   godot --headless --path . --script res://tests/probe_prop_density.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const RADIUS := 20000.0
const BANDS := [0.03, 0.06, 0.12, 0.25]

var _globe: Node3D
const FACES_CAST := preload("res://core/frame/math/icosahedral_faces.gd")


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
	# THE ASYNC PROP LAW (v6): trees/details/grass derive on worker
	# threads; the census waits for the pending derive jobs to drain
	# (bounded) before counting. v9: the MESH lane rides the same
	# drain (pending_derive covers both) -- the neighbor patches land
	# off-thread now, and the census reads a steady world.
	var waited := 0
	while _globe.get("streamer").pending_derive() > 0 and waited < 1200:
		await root.get_tree().physics_frame
		waited += 1
	print("PENDING_DRAINED_after=", waited + 90, " frames, tmsec=", Time.get_ticks_msec() - t0)

	var streamer = _globe.get("streamer")
	var player = _globe.get("player")
	var planet_center: Vector3 = _globe.get("planet_center")
	var radius_pl: float = _globe.get("planet_radius")
	var pdir: Vector3 = (player.global_position - planet_center).normalized()

	var band_counts: Dictionary = {}
	for b in BANDS:
		band_counts[b] = {"rock": 0, "boulder": 0, "tree": 0, "detail": 0}
	var total := {"rock": 0, "boulder": 0, "tree": 0, "detail": 0}
	var holders_empty := 0
	var nearest: Array = []  # [ground_m, kind, face]
	var face_report: Array = []
	var active: Array = streamer.active_faces()

	for face in active:
		var mi = streamer._patches.get(face)
		if mi == null:
			continue
		var lvl: int = int(streamer._patch_lvl.get(face, -1))
		var holder: Node3D = streamer._prop_holders.get(face)
		var per := {"rock": 0, "boulder": 0, "tree": 0, "detail": 0}
		if holder == null or holder.get_child_count() == 0:
			holders_empty += 1
			face_report.append("face=%d lvl=%d EMPTY" % [face, lvl])
			continue
		var name_samples: Array = []
		for ch in holder.get_children():
			if ch is CollisionObject3D or not (ch is Node3D):
				continue
			# THE GRASS FIELD (v6 meadow law): one MultiMesh per face --
			# the blade mass is its instance_count (count as detail).
			if String(ch.name).begins_with("GrassField"):
				var gmm = ch.get("multimesh")
				if gmm != null:
					per["detail"] = int(per["detail"]) + int(gmm.instance_count)
					total["detail"] = int(total["detail"]) + int(gmm.instance_count)
				continue
			if name_samples.size() < 10:
				name_samples.append(String(ch.name))
			var cname := String(ch.name)
			var kind := _kind_of(cname)
			# The tree batch flush: one MultiMesh pair per face paints
			# every non-node tree -- the MESH COUNT is inside the batch.
			if kind == "detail" and (cname.begins_with("BatchedTrunks") \
					or cname.begins_with("BatchedCanopies")):
				if cname.begins_with("BatchedTrunks"):
					var mm = ch.get("multimesh")
					if mm != null:
						per["tree"] = int(per["tree"]) + int(mm.instance_count)
						total["tree"] = int(total["tree"]) + int(mm.instance_count)
				continue
			if kind == "detail" and not _looks_detail(cname):
				continue
			per[kind] = int(per[kind]) + 1
			total[kind] = int(total[kind]) + 1
			var pw: Vector3 = (ch.global_position - planet_center).normalized()
			var ang: float = pw.angle_to(pdir)
			var ground_m: float = ang * radius_pl
			nearest.append([ground_m, kind, face])
			for b in BANDS:
				if ang <= float(b):
					band_counts[b][kind] = int(band_counts[b][kind]) + 1
					break
		face_report.append("face=%d lvl=%d %s props names=%s" % [face, lvl, str(per), str(name_samples)])

	print("player r-planet=", (player.global_position - planet_center).length() - radius_pl,
		" ACTIVE_FACES=", active.size(),
		" BASE_LEVEL=", streamer._level_for_edge())
	for line in face_report:
		print("  ", line)
	print("TOTALS=", str(total), " EMPTY_HOLDERS=", holders_empty)
	for i in range(mini(12, nearest.size())):
		print("  NEAREST %02d: ground=%6.0f m kind=%s face=%d" % [i, nearest[i][0], nearest[i][1], nearest[i][2]])
	for b in BANDS:
		var bc: Dictionary = band_counts[b]
		print("BAND <=%4.2f rad (%5.0f m): rock=%d boulder=%d tree=%d detail=%d" %
			[float(b), float(b) * radius_pl, bc["rock"], bc["boulder"], bc["tree"], bc["detail"]])
	quit(0)


func _looks_detail(base: String) -> bool:
	for pre in ["Cattail", "Ore", "Bush", "Tuft", "Flower", "Reed", "Detail"]:
		if base.begins_with(pre):
			return true
	return false
