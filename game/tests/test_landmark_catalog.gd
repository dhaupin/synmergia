# test_landmark_catalog.gd - THE ATLAS RECEIPT: every named place in
# data/landmarks/ must be identity, and the neighbouring systems keep their
# own law:
#
#   A. THE CATALOG: DataService.load_landmarks() loads the seven shipped
#      anchors and resolves each by id.
#   B. POSITION LAW: a positioned landmark's dir is unit length (the same
#      sphere space terrain_gen's anchors use); a zero dir is legal only for
#      a band (The Home Ring) or a world-level entry (The Deep Root).
#   C. REFERENCE LAW: every zone_id and gateway_id resolves, and no landmark
#      ever names a player pin (landmarks are shared, pins are personal).
#   D. TRAVEL LAW: is_travel_point() is exactly "gateway_id is set" --
#      a landmark never carries its own activation rule.
#
# Receipt-lore: script-mode law -- autoloads resolved from root at runtime;
# failures name the landmark id.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

const EXPECTED := [
	"landmark_haven_shore",
	"landmark_novo_concord",
	"landmark_gull_island",
	"landmark_high_tarn",
	"landmark_home_ring",
	"landmark_sundered_strait",
	"landmark_deep_root",
]


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
	print("--- LANDMARK CATALOG: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)
	if ds == null:
		_finish()
		return

	ds.load_all_data()
	ds.load_landmarks()

	var all: Array = ds.get_all_landmarks()
	_check("landmark catalog loads (%d)" % all.size(), all.size() >= EXPECTED.size())

	# A. every shipped anchor resolves by id.
	for eid in EXPECTED:
		_check("%s resolves" % eid, ds.get_landmark(eid) != null)

	# B. position law.
	var non_unit: Array = []
	for lm in all:
		if lm.has_position() and absf(lm.dir.length() - 1.0) > 0.001:
			non_unit.append(lm.id)
	_check("every positioned landmark dir is unit length", non_unit.is_empty())

	var ring = ds.get_landmark("landmark_home_ring")
	_check("Home Ring is a band, not a point", ring != null and not ring.has_position())
	var deep = ds.get_landmark("landmark_deep_root")
	_check("Deep Root is world-level (underworld)",
		deep != null and deep.world_id == "underworld" and not deep.has_position())

	var haven = ds.get_landmark("landmark_haven_shore")
	_check("Haven Shore sits at SPAWN_CENTER (1,0,0)",
		haven != null and haven.dir_normalized().distance_to(Vector3(1, 0, 0)) < 0.001)

	# C. reference law.
	var bad_zones: Array = []
	for lm in all:
		if lm.zone_id != "" and ds.get_zone(lm.zone_id) == null:
			bad_zones.append("%s -> %s" % [lm.id, lm.zone_id])
	_check("every landmark zone_id resolves", bad_zones.is_empty())

	var bad_gates: Array = []
	for lm in all:
		if lm.gateway_id != "" and ds.get_gateway(lm.gateway_id) == null:
			bad_gates.append("%s -> %s" % [lm.id, lm.gateway_id])
	_check("every landmark gateway_id resolves", bad_gates.is_empty())

	var pinned: Array = []
	for lm in all:
		if lm.gateway_id.begins_with("waypoint:player"):
			pinned.append(lm.id)
	_check("no landmark references a player pin", pinned.is_empty())

	# D. travel law lives on the gateway, never on the landmark.
	var travel_mismatch: Array = []
	for lm in all:
		var has_gw: bool = lm.gateway_id != ""
		if lm.is_travel_point() != has_gw:
			travel_mismatch.append(lm.id)
	_check("is_travel_point() is exactly a gateway backref", travel_mismatch.is_empty())
	_check("landmarks carry no activation state",
		not ("activation_requirement" in all[0]) and not ("gateway_type" in all[0]))

	_check("unknown landmark returns null", ds.get_landmark("landmark_does_not_exist") == null)

	_finish()
