## diag_detail_kinds - FIELD-1 closure diagnostic. Boots the planet
## at the ordinary 20 km scale and answers, for the boot faces:
##   1) DERIVE histogram: records _derive_detail_sites returns (kind -> n)
##   2) HOLDER census: node kinds the live faces carry
##   3) BAND PASS: derive-site ground distances from the boot
##   4) FIELD-3 GROUND PASS: applied node radial length vs the surface
##      band (sit-on-ground check; meters-scale slop is expected)
## Run headless: godot --headless --path . --script res://tests/diag_detail_kinds.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const BANDS := [0.01, 0.03, 0.06, 0.12]  # m = rad * radius

var _globe: Node


func _init() -> void:
	call_deferred("_run")


func _hist_names(node: Node3D) -> Dictionary:
	var hist := {}
	for ch in node.get_children():
		var base := String(ch.name)
		var cut := base.rfind("0")
		var kind := base.substr(0, cut + 1 if cut >= 0 else base.length())
		var mm: MultiMesh = ch.get("multimesh")
		var n: int = mm.instance_count if mm != null else 1
		hist[kind] = int(hist.get(kind, 0)) + n
	return hist


func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(10):
		await process_frame
	var streamer = _globe.get("streamer")
	var waited := 0
	while streamer.pending_derive() > 0 and waited < 300:
		await root.get_tree().physics_frame
		waited += 1
	for _i in range(20):
		await root.get_tree().physics_frame
	print("DIAG drained after=", waited, " tmsec=", Time.get_ticks_msec())

	var holder_prefixes := ["Tuft", "Flower", "Bush", "Cattail", "Ore", "Mushroom", "Mycelium", "GrassField", "DetailTuftBatch", "Scree", "Rock", "Tree"]
	var pc: Vector3 = _globe.get("planet_center")
	var r: float = _globe.get("planet_radius")
	var player = _globe.get("player")
	var pdir: Vector3 = (player.global_position - pc).normalized()
	for face in streamer.active_faces():
		var sites: Array = streamer._derive_detail_sites(face)
		var kinds := {}
		var bands := {}
		for b in BANDS:
			bands[float(b)] = 0
		for rec in sites:
			kinds[int(rec["kind"])] = int(kinds.get(int(rec["kind"]), 0)) + 1
			var dpos: Vector3 = rec["pos"]
			var wp: Vector3 = pc + dpos - r * ((pc + dpos).normalized())
			var ang: float = wp.angle_to(pdir)
			for b in BANDS:
				if ang <= float(b):
					bands[float(b)] = int(bands[float(b)]) + 1
					break
		var holder = streamer._prop_holders.get(face)
		var hh := {}
		if holder != null:
			for ch in holder.get_children():
				var nm := String(ch.name)
				var hit := false
				for pre in holder_prefixes:
					if nm.begins_with(pre):
						var mm: MultiMesh = ch.get("multimesh")
						var n: int = mm.instance_count if mm != null else 1
						hh[pre] = int(hh.get(pre, 0)) + n
						hit = true
						break
				if not hit:
					hh["?"] = int(hh.get("?", 0)) + 1
		# FIELD-3 pass: node radial length vs the surface radius at its
		# own direction.
		var worst_below := -9999.0
		var worst_above := -9999.0
		var bad := 0
		var checked := 0
		var patch: Node3D = streamer._patches.get(face)
		if holder != null and patch != null:
			var ptx: Transform3D = patch.global_transform
			for ch in holder.get_children():
				var nm := String(ch.name)
				var kind_hit := false
				for pre in ["Flower", "Bush", "Mushroom", "Cattail", "Mycelium", "Ore"]:
					if nm.begins_with(pre):
						kind_hit = true
						break
				if not kind_hit:
					continue  # the pass audits the DETAIL tier's own kinds
				var wp: Vector3 = ptx * (ch as Node3D).position
				var ndir: Vector3 = (wp - pc).normalized()
				var gh: float = float(streamer.call("_prop_site_ground_h", ndir, face)) if streamer.terrain_on else 0.0
				var surf: float = r + gh
				var over: float = wp.length() - surf
				checked += 1
				worst_below = max(worst_below, -over)
				worst_above = max(worst_above, over)
				if over < -8.0 or over > 12.0:
					bad += 1
		var band_str := ""
		for b in BANDS:
			band_str += "%dm=%d " % [int(float(b) * r), bands[float(b)]]
		print("face=%d lvl=%s DERIVE_kinds=%s DERIVE_bands='%s' HOLDER=%s FIELD3 checked=%d below=%.2f above=%.2f bad=%d" % [
			face, str(streamer._patch_lvl.get(face, -1)), str(kinds),
			band_str.strip_edges(), str(hh), checked,
			worst_below, worst_above, bad])
	quit(0)
