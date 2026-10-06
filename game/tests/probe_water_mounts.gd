# probe_water_mounts.gd - S14.6: water mounts are rated bodies
# (labs/prd-ocean-depths.md sec 7).
#
# Covers:
#   A. Declarations: the three water mounts load, filename == id, kind
#      AQUATIC, is_swimmer() honest, hitbox profiles resolve (water
#      mounts share the HitboxProfile system).
#   B. The dismount law: land mounts bail at the waterline
#      (MOUNT_DISMOUNT_ON_SUBMERGE -- the glider cliff rule's water
#      twin); water mounts ride every band.
#   C. THE BODY-RATING LAW: crush_depth_bonus_m is the one thing that
#      moves CRUSH (gear grace never does); squeeze grace deepens the
#      squeeze line, and breather + mount grace ADD.
#   D. tick_swimmer integration: the wyrm at 62 m swims (SQUEEZE)
#      where anything else is CRUSH.
#   E. Current immunity: effective_current zeroes for the immune body
#      (the anticheat stamp reads THIS; a zero stamp erases the
#      passive-drift forgiveness).
#   F. Mounted limits: the anticheat's aquatic book stamps the mount's
#      cruise speed (the ray's 9 m/s cruise never trips; a 20 m/s
#      "fish" trips within the sustained window).
#
# Script mode: autoloads resolved at runtime (OceanService,
# AntiCheatService).
extends SceneTree

const SUSTAINED: int = 32  # AntiCheatService.SUSTAINED_FRAME_LIMIT + margin

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("PASS: ", label)
	else:
		_fails += 1
		print("FAIL: ", label)

func _run() -> void:
	var ocean = root.get_node_or_null("OceanService")
	var ac = root.get_node_or_null("AntiCheatService")
	_check("OceanService present", ocean != null)
	_check("AntiCheatService present", ac != null)
	if ocean == null or ac == null:
		quit(1)
		return
	var SS: GDScript = load("res://core/frame/srv/swim_state.gd")
	var MDS: GDScript = load("res://core/schemas/mount_data.gd")
	var OVS: GDScript = load("res://core/schemas/ocean_volume.gd")
	var B = OVS.DepthBand

	# ---- A. Declarations -------------------------------------------------------
	ocean.ensure_loaded()
	var shelf = ocean.get_volume("ocean_haven_shelf")
	_check("the shelf loads (the proving ground)", shelf != null)
	var glider = load("res://data/mounts/mount_reef_glider.tres")
	var ray = load("res://data/mounts/mount_pearl_ray.tres")
	var wyrm = load("res://data/mounts/mount_trench_wyrm.tres")
	_check("all three water mounts load", glider != null and ray != null and wyrm != null)
	_check("ids match filenames (naming law)", \
		str(glider.id) == "mount_reef_glider" and str(ray.id) == "mount_pearl_ray" \
		and str(wyrm.id) == "mount_trench_wyrm")
	_check("kind is AQUATIC for all three", \
		glider.kind == MDS.MountKind.AQUATIC and ray.kind == MDS.MountKind.AQUATIC \
		and wyrm.kind == MDS.MountKind.AQUATIC)
	_check("is_swimmer(): the speed is what makes a swimmer", \
		glider.is_swimmer() and ray.is_swimmer() and wyrm.is_swimmer())
	_check("declared cruise speeds: glider 7, ray 9, wyrm 8", \
		absf(glider.swim_speed - 7.0) < 0.001 and absf(ray.swim_speed - 9.0) < 0.001 \
		and absf(wyrm.swim_speed - 8.0) < 0.001)
	var hm = load("res://data/hitbox_profiles/hitbox_swimmer_medium.tres")
	var hl = load("res://data/hitbox_profiles/hitbox_swimmer_large.tres")
	_check("swimmer hitbox profiles load", hm != null and hl != null)
	_check("mount hitbox refs resolve (shared HitboxProfile system)", \
		str(glider.hitbox_profile_id) == "hitbox_swimmer_medium" \
		and str(ray.hitbox_profile_id) == "hitbox_swimmer_medium" \
		and str(wyrm.hitbox_profile_id) == "hitbox_swimmer_large" \
		and str(hm.id) == "hitbox_swimmer_medium" and str(hl.id) == "hitbox_swimmer_large")

	# ---- B. The dismount law ------------------------------------------------------
	_check("the law exists: MOUNT_DISMOUNT_ON_SUBMERGE", SS.MOUNT_DISMOUNT_ON_SUBMERGE == true)
	_check("a land mount wades with its rider", SS.mount_band_allowed(false, SS.State.WADING))
	_check("a land mount bails when the body is in the water", \
		not SS.mount_band_allowed(false, SS.State.SURFACE_SWIM))
	_check("a land mount bails when submerged", \
		not SS.mount_band_allowed(false, SS.State.SUBMERGED))
	_check("a water mount rides every band (its rating is the limiter, not a gate)", \
		SS.mount_band_allowed(true, SS.State.SUBMERGED) and SS.mount_band_allowed(true, SS.State.CRUSH))

	# ---- C. The body-rating law -----------------------------------------------------
	_check("62 m on the shelf is CRUSH for the unrated", shelf.band_for(62.0) == B.CRUSH)
	_check("the wyrm's rating moves the stone: 62 m is SQUEEZE for it", \
		shelf.band_for(62.0, 0.0, 30.0) == B.SQUEEZE)
	_check("the rating is finite: 95 m is CRUSH even for the wyrm", \
		shelf.band_for(95.0, 0.0, 30.0) == B.CRUSH)
	_check("GEAR never moves crush: grace 20 at 62 m is still CRUSH", \
		shelf.band_for(62.0, 20.0) == B.CRUSH)
	_check("ray grace deepens the squeeze line: 55 m is free water on the ray", \
		shelf.band_for(55.0, 6.0) == B.SUBMERGED)
	_check("56 m on the ray is the squeeze line exactly (50 + 6)", \
		shelf.band_for(56.0, 6.0) == B.SQUEEZE)

	# ---- D. tick integration --------------------------------------------------------
	var d62 := Vector3(3000, -62, 0)
	var d56 := Vector3(3000, -56, 0)
	var r1 = ocean.tick_swimmer("wm_unrated", d62, 1.0 / 60.0)
	_check("an unrated body at 62 m reads CRUSH", int(r1.band) == B.CRUSH)
	var r2 = ocean.tick_swimmer("wm_wyrm", d62, 1.0 / 60.0, 0.0, 0.0, float(wyrm.crush_depth_bonus_m))
	_check("the wyrm at 62 m swims: SQUEEZE, not CRUSH", \
		int(r2.band) == B.SQUEEZE and int(r2.state) == SS.State.SQUEEZE)
	var r3 = ocean.tick_swimmer("wm_ray_plus_breather", d56, 1.0 / 60.0, 8.0, float(ray.squeeze_grace_m))
	_check("breather x8 + ray grace ADD: 56 m is free water", int(r3.band) == B.SUBMERGED)
	var r4 = ocean.tick_swimmer("wm_ray_only", d56, 1.0 / 60.0, 0.0, float(ray.squeeze_grace_m))
	_check("ray grace alone puts 56 m on the squeeze line", int(r4.band) == B.SQUEEZE)

	# ---- E. Current immunity ---------------------------------------------------------
	var shelf_pos := Vector3(3000, -5, 0)
	_check("the shelf declares a current (the ferry lane)", ocean.current_at(shelf_pos) != Vector3.ZERO)
	_check("the immune body feels NO drift", ocean.effective_current(shelf_pos, true) == Vector3.ZERO)
	_check("the ordinary body feels the declared current", \
		ocean.effective_current(shelf_pos, false) == ocean.current_at(shelf_pos))

	# ---- F. Mounted limits --------------------------------------------------------------
	ac.register_player("wm_ray_rider")
	ac.set_aquatic_limits("wm_ray_rider", float(ray.swim_speed), 18.0, 3.0)
	var tripped := false
	for i in range(SUSTAINED):
		if ac.validate_movement("wm_ray_rider", Vector3(10.0 + i, -2.0, 0.0), \
				Vector3(ray.swim_speed, 0.0, 0.0), 1.0 / 60.0):
			tripped = true
	_check("the ray's 9 m/s cruise never trips the validator", not tripped)
	ac.register_player("wm_hacker")
	ac.set_aquatic_limits("wm_hacker", 9.0, 18.0, 3.0)
	var fish_tripped := false
	for i in range(SUSTAINED + 2):
		if ac.validate_movement("wm_hacker", Vector3(50.0 + i, -2.0, 0.0), \
				Vector3(30.0, 0.0, 0.0), 1.0 / 60.0):
			fish_tripped = true
	_check("a 30 m/s 'fish' trips it within the sustained window (the ray's ceiling is 22.5)", fish_tripped)
	ac.unregister_player("wm_ray_rider")
	ac.unregister_player("wm_hacker")

	print("probe_water_mounts: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
