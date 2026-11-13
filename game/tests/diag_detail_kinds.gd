## diag_detail_kinds - v9 world-dressing diagnostic. Boots the planet
## at the ordinary 20 km scale:
##   1) Boot-face census: derive kinds + holder kinds.
##   2) FIELD-3 GROUND PASS (honest): every detail-kind node and every
##      tuft-batch instance whose radial over/under the analytic
##      surface is measured AGAINST planet_center (the world is
##      re-rooted near the player at planet scale, so the radius from
##      the world origin is not the ground radius).
##   3) THE TRAVEL CENSUS (GM travel): derive the detail tier across
##      ALL 20 base faces and bucket every SITE by ITS OWN band --
##      what a biome holds when a GM arrives, per site, not per face
##      center guess.
## Run headless: godot --headless --path . --script res://tests/diag_detail_kinds.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const KIND_NAMES := {0: "ore", 1: "cattail", 2: "bush", 3: "tuft", 4: "flower", 5: "mushroom", 6: "mycelium", 7: "shell", 8: "wrack"}
const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

var _globe: Node


func _init() -> void:
	# This probe reads the icosa STREAMER internals; pin the renderer
	# so the default (clipmap) does not change what it inspects.
	ProjectSettings.set_setting("synmergia/world/terrain_render", "streamer")
	call_deferred("_run")


func _over_run(streamer, pc: Vector3, r: float, wp: Vector3, face: int, out: Dictionary) -> void:
	var ndir: Vector3 = (wp - pc).normalized()
	var gh: float = float(streamer.call("_prop_site_ground_h", ndir, face)) if bool(streamer.terrain_on) else 0.0
	var over: float = (wp - pc).length() - (r + gh)
	out["checked"] = int(out["checked"]) + 1
	out["worst_below"] = max(float(out["worst_below"]), -over)
	out["worst_above"] = max(float(out["worst_above"]), over)
	# THE SLOP HISTOGRAM: a systematic frame offset prints one big
	# far-bucket mass; relief slope prints a dense near-zero spread.
	var buck := "<-50/-8..-1/-1..1/1..3/>3"
	if over < -50.0:
		buck = "deep"
	elif over < -8.0:
		buck = "sunk"
	elif over < -1.0:
		buck = "low"
	elif over <= 1.0:
		buck = "seat"
	elif over <= 3.0:
		buck = "proud"
	else:
		buck = "float"
	out[buck] = int(out.get(buck, 0)) + 1
	if over < -8.0 or over > 12.0:
		out["bad"] = int(out["bad"]) + 1


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

	var pc: Vector3 = _globe.get("planet_center")
	var r: float = _globe.get("planet_radius")
	var holder_prefixes := ["Flower", "Bush", "Mushroom", "Cattail", "Ore", "Mycelium", "GrassField", "DetailTuftBatch", "Scree", "Rock", "Tree"]
	var audit := {"checked": 0, "worst_below": -9999.0, "worst_above": -9999.0, "bad": 0}
	# --- 1) boot faces: kinds + holder census -----------------------
	var stretch: Array = streamer.active_faces()
	for face in stretch:
		var sites: Array = streamer._derive_detail_sites(face)
		var kinds := {}
		for rec in sites:
			kinds[KIND_NAMES.get(int(rec["kind"]), "?")] = int(kinds.get(KIND_NAMES.get(int(rec["kind"]), "?"), 0)) + 1
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
		print("face=%d lvl=%s DERIVE=%s HOLDER=%s" % [
			face, str(streamer._patch_lvl.get(face, -1)), str(kinds), str(hh)])
	# --- 2) FIELD-3 (honest, pc-relative) on the NEAR faces ---------
	for face in stretch:
		var lvl: int = int(streamer._patch_lvl.get(face, -1))
		if lvl != int(streamer._level_for_edge()):
			continue  # audit the interior renders the player stands on
		var patch: Node3D = streamer._patches.get(face)
		var holder = streamer._prop_holders.get(face)
		if holder == null or patch == null:
			continue
		for ch in holder.get_children():
			var nm: String = String(ch.name)
			var is_det := false
			for pre in ["Flower", "Bush", "Mushroom", "Cattail", "Mycelium", "Ore"]:
				if nm.begins_with(pre):
					is_det = true
					break
			if is_det:
				_over_run(streamer, pc, r, (ch as Node3D).global_position, face, audit)
			elif nm.begins_with("DetailTuftBatch"):
				var gmi: Node3D = ch
				var mm2: MultiMesh = gmi.get("multimesh")
				var btx: Transform3D = gmi.global_transform
				var dump := ""
				for t in range(mini(3, mm2.instance_count)):
					var xt: Transform3D = mm2.get_instance_transform(t)
					dump += " inst%d=(%.1f,%.1f,%.1f)" % [t, xt.origin.x, xt.origin.y, xt.origin.z]
				var x0: Transform3D = mm2.get_instance_transform(0)
				var wp0: Vector3 = btx * x0.origin
				print("  TUFT_DUMP face=%d gmi.basis_scale=[%s] holder.basis=[%s]%s wp0=(%.1f,%.1f,%.1f) radial_over_pc=%.2f" % [
					face, str((gmi as Node3D).basis.get_scale()),
					str((holder as Node3D).basis.get_scale()), dump,
									wp0.x, wp0.y, wp0.z, (wp0 - pc).length() - r])

				for t in range(mm2.instance_count):
					_over_run(streamer, pc, r, btx * mm2.get_instance_transform(t).origin, face, audit)


	# THE COMPARE PROBE: fresh-derive the k-th tuft rec for the deep
	# face and line it up against the LIVE batch's stored instance at
	# the same index -- if they diverge, the APPLY stored a different
	# transform than the derive law; if they match, the audit map is
	# the wrong side of the ledger.
	var deep_reports := ""
	for face in stretch:
		var lvl: int = int(streamer._patch_lvl.get(face, -1))
		if lvl != int(streamer._level_for_edge()):
			continue
		var patch: Node3D = streamer._patches.get(face)
		var holder = streamer._prop_holders.get(face)
		if holder == null or patch == null:
			continue
		var fresh: Array = streamer._derive_detail_sites(face)
		var tuft_recs: Array = []

		for rec in fresh:
			if int(rec["kind"]) == 3:
				tuft_recs.append(rec)
		for ch in holder.get_children():
			if not String(ch.name).begins_with("DetailTuftBatch"):
				continue
			var mmx: MultiMesh = (ch as Node3D).get("multimesh")
			var btxx: Transform3D = (ch as Node3D).global_transform
			for k in range(0, mini(120, mmx.instance_count)):
				var stored: Vector3 = mmx.get_instance_transform(k).origin
				var law: Vector3 = tuft_recs[k]["pos"] if k < tuft_recs.size() else stored
				var w_stored: Vector3 = btxx * stored
				var w_law: Vector3 = btxx * law
				deep_reports += " t%d stored=(%.1f,%.1f,%.1f) law=(%.1f,%.1f,%.1f) radial_stored=%.2f radial_law=%.2f" % [
					k, stored.x, stored.y, stored.z, law.x, law.y, law.z,
					(w_stored - pc).length() - r, (w_law - pc).length() - r]
	print("COMPARE %s" % deep_reports)
	print("FIELD3 checked=%d worst_below=%.2f worst_above=%.2f bad=%d hist={seat=%d proud=%d low=%d sunk=%d deep=%d float=%d}" % [
		int(audit["checked"]), float(audit["worst_below"]),
		float(audit["worst_above"]), int(audit["bad"]),
		int(audit.get("seat", 0)), int(audit.get("proud", 0)),
		int(audit.get("low", 0)), int(audit.get("sunk", 0)),
		int(audit.get("deep", 0)), int(audit.get("float", 0))])
	# --- 3) THE TRAVEL CENSUS (per-SITE band across all 20 faces) ---
	var by_band := {}
	for f in range(20):
		var sites: Array = streamer._derive_detail_sites(f)
		for rec in sites:
			var band_key: int = int(rec.get("bid", -1))
			var kind_key: String = str(KIND_NAMES.get(int(rec["kind"]), "?"))
			var bucket: Dictionary = by_band.get(band_key, {})
			bucket[kind_key] = int(bucket.get(kind_key, 0)) + 1
			by_band[band_key] = bucket
	for band_key in by_band:
		print("BIOME id=%d sites_by_kind=%s" % [band_key, str(by_band[band_key])])
	quit(0)
