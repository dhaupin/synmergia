# test_map_landmark_wiring.gd - THE NO-ORPHAN RECEIPT: the landmark atlas
# must have real consumers, not just a catalog and a lint gate.
#
#   A. BIG MAP DRAWS THE ATLAS: world_map.sync_landmark_markers() creates a
#      marker per positioned main-world landmark.
#   B. BANDS ARE NOT DOTS: a landmark with no position (the Home Ring) never
#      draws a point.
#   C. DEDUPE: a place named by the atlas does not ALSO draw from the legacy
#      zone/gateway stitching -- Haven Shore appears exactly once.
#   D. MINIMAP READS IDENTITY: the zone/gateway name lookups resolve through
#      the atlas (Gull Island by zone, Sundered Strait by gateway backref).
#
# Receipt-lore: script-mode law -- autoloads resolved from root; the map
# components are instantiated bare (no scene) and only their marker book is
# inspected, so no rendering is required.
extends SceneTree

var _fails: int = 0
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)


func _finish() -> void:
	print("--- MAP LANDMARK WIRING: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)
	if ds == null:
		_finish()
		return
	ds.load_all_data()
	ds.load_landmarks()

	# A. the big map draws the atlas.
	var wm_script = load("res://ui/components/world_map.gd")
	_check("world_map script loads", wm_script != null)
	if wm_script == null:
		_finish()
		return
	var wm = wm_script.new()
	root.add_child(wm)
	await process_frame
	wm.sync_landmark_markers()
	var markers: Variant = wm.get("_entity_markers")
	_check("world_map keeps a marker book", markers is Dictionary)
	if not (markers is Dictionary):
		wm.free()
		_finish()
		return

	_check("the big map draws a point landmark (High Tarn)",
		markers.has("LANDMARK_atlas_landmark_high_tarn"))
	_check("the big map draws a settled place (Haven Shore)",
		markers.has("LANDMARK_atlas_landmark_haven_shore"))

	# B. a band has no dot.
	_check("a band landmark never draws a dot (Home Ring)",
		not markers.has("LANDMARK_atlas_landmark_home_ring"))
	_check("a world-level landmark stays off the main map (Deep Root)",
		not markers.has("LANDMARK_atlas_landmark_deep_root"))

	# C. dedupe: Haven Shore once, atlas wins over the zone stitch.
	var haven_labels: int = 0
	for k in markers:
		var data: Variant = markers[k]
		if data is Dictionary and str(data.get("label", "")) == "Haven Shore":
			haven_labels += 1
	_check("Haven Shore draws exactly once (atlas dedupes the zone stitch)",
		haven_labels == 1)

	# A marker that the atlas controls must carry the atlas position (the
	# sphere direction), not a zone bind point.
	var high_tarn: Variant = markers.get("LANDMARK_atlas_landmark_high_tarn")
	var positioned: bool = false
	if high_tarn is Dictionary:
		var p: Variant = high_tarn.get("position", Vector3.ZERO)
		if p is Vector3:
			positioned = (p as Vector3).length() > 1.0
	_check("the atlas marker carries a sphere position", positioned)

	wm.free()

	# D. minimap identity lookups.
	var mm_script = load("res://ui/components/minimap.gd")
	_check("minimap script loads", mm_script != null)
	if mm_script != null:
		var mm = mm_script.new()
		var gull = mm._atlas_landmark_for_zone("zone_gull_island")
		_check("minimap resolves a zone name through the atlas",
			gull != null and str(gull.get("display_name")) == "Gull Island")
		var strait = mm._atlas_landmark_for_gateway("waypoint_strait_moor")
		_check("minimap resolves a gateway name through the atlas",
			strait != null and str(strait.get("display_name")) == "The Sundered Strait")
		_check("minimap returns null for an unnamed zone",
			mm._atlas_landmark_for_zone("zone_no_such_zone") == null)
		mm.free()

	_finish()
