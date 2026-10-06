# probe_riding.gd - the riding layer ties land, water, sky, and space
# mounts (labs/prd-mounts.md).
#
# Covers:
#   A. Sky declarations: the three elite mounts load, filename == id,
#      kind FLYING, their OWN movement profiles resolve (the Movement
#      Design System owns speeds -- one profile per elite body),
#      hitbox refs resolve, and the acquisition law is elite (level
#      50+, not vendor-priced, soulbound).
#   B. The ownership ledger: grant refuses unknowns and duplicates,
#      persists through the DictStore (the wake-ledger idiom).
#   C. Summon stamps: the anticheat is judged by the MOUNT's profile
#      (the lancer's 21 m/s sprint is a 52.5 legal ceiling); dismiss
#      hands the body back humanoid limits.
#   D. The water handoff: water mounts return the S14.6 swim stamp
#      (speed/grace/crush/immune), land mounts DISMOUNT at the
#      waterline (book cleared, limits restamped), wading rides, no
#      mount is "none".
#   E. Space-ready: MountKind.SPACE exists and rides the same path.
#
# Script mode: autoloads resolved at runtime (RideService,
# AntiCheatService, DataService).
extends SceneTree

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
	var rides = root.get_node_or_null("RideService")
	var ac = root.get_node_or_null("AntiCheatService")
	var ds = root.get_node_or_null("DataService")
	_check("RideService present", rides != null)
	_check("AntiCheatService present", ac != null)
	_check("DataService present", ds != null)
	if rides == null or ac == null or ds == null:
		quit(1)
		return
	var MDS: GDScript = load("res://core/schemas/mount_data.gd")
	var DS: GDScript = preload("res://adapters/persistence/dict_store.gd")

	# ---- A. Sky declarations ------------------------------------------------
	var lancer = ds.get_mount("mount_storm_lancer")
	var soarer = ds.get_mount("mount_skyreef_soarer")
	var moth = ds.get_mount("mount_moonwing_moth")
	_check("all three sky mounts load", lancer != null and soarer != null and moth != null)
	_check("ids match filenames (naming law)", \
		str(lancer.id) == "mount_storm_lancer" and str(soarer.id) == "mount_skyreef_soarer" \
		and str(moth.id) == "mount_moonwing_moth")
	_check("kind is FLYING for all three", \
		lancer.kind == MDS.MountKind.FLYING and soarer.kind == MDS.MountKind.FLYING \
		and moth.kind == MDS.MountKind.FLYING)
	_check("each elite rides its OWN movement profile", \
		str(lancer.movement_profile_id) == "movement_sky_lancer" \
		and str(soarer.movement_profile_id) == "movement_sky_soarer" \
		and str(moth.movement_profile_id) == "movement_sky_moth")
	var lp = ds.get_mount_movement_profile(lancer)
	_check("the lancer's profile resolves through the one path (explicit wins)", \
		lp != null and str(lp.id) == "movement_sky_lancer")
	_check("the acquisition law is elite: level 50+, not vendor-priced, soulbound", \
		int(lancer.required_level) >= 50 and int(soarer.required_level) >= 55 \
		and int(moth.required_level) >= 50 and int(lancer.cost) == 0 \
		and int(soarer.cost) == 0 and bool(lancer.soulbound))
	var mhl = load("res://data/hitbox_profiles/hitbox_sky_large.tres")
	_check("the soarer's sky hitbox loads and refs resolve", \
		mhl != null and str(soarer.hitbox_profile_id) == "hitbox_sky_large" \
		and str(mhl.id) == "hitbox_sky_large")

	# ---- B. The ownership ledger ----------------------------------------------
	_check("grant refuses an unknown mount", not rides.grant_mount("pr_r1", "mount_does_not_exist"))
	_check("grant accepts the lancer", rides.grant_mount("pr_r1", "mount_storm_lancer"))
	_check("grant refuses duplicates (soulbound posture)", not rides.grant_mount("pr_r1", "mount_storm_lancer"))
	_check("the rider owns the lancer", rides.owns_mount("pr_r1", "mount_storm_lancer"))
	var store = DS.new()
	var row = store.get_kv("ride_service/mounts/pr_r1", null)
	_check("ownership persisted through the DictStore (the wake-ledger idiom)", \
		row is Dictionary and row.has("mount_storm_lancer"))

	# ---- C. Summon stamps ---------------------------------------------------------
	_check("summon accepts an owned mount", rides.summon("pr_r1", "mount_storm_lancer"))
	var lim = ac.get_movement_limits("pr_r1")
	_check("the body is judged by the MOUNT's profile (21 m/s sprint = 52.5 ceiling)", \
		absf(float(lim.get("max_speed", 0.0)) - 52.5) < 0.01)
	_check("the mount's jump stamps too (16 x 2.5 = 40)", \
		absf(float(lim.get("max_jump", 0.0)) - 40.0) < 0.01)
	_check("dismiss hands the body back humanoid limits", rides.dismiss("pr_r1") \
		and absf(float(ac.get_movement_limits("pr_r1").get("max_speed", 0.0)) - 25.0) < 0.01)

	# ---- D. The water handoff -------------------------------------------------------
	_check("grant the pearl ray", rides.grant_mount("pr_r2", "mount_pearl_ray"))
	_check("summon the ray", rides.summon("pr_r2", "mount_pearl_ray"))
	var s1 = rides.water_stamp_for("pr_r2", 3)
	_check("the ray at depth: the S14.6 swim stamp (speed 9, grace 6)", \
		str(s1.get("action", "")) == "swim" and absf(float(s1.get("speed", 0.0)) - 9.0) < 0.001 \
		and absf(float(s1.get("grace", 0.0)) - 6.0) < 0.001)
	_check("grant + summon the reef glider", rides.grant_mount("pr_r3", "mount_reef_glider") \
		and rides.summon("pr_r3", "mount_reef_glider"))
	var s2 = rides.water_stamp_for("pr_r3", 5)
	_check("the glider's stamp carries current immunity (it swims its own vector)", \
		str(s2.get("action", "")) == "swim" and bool(s2.get("immune", true)))
	_check("grant + summon the wyrm", rides.grant_mount("pr_r4", "mount_trench_wyrm") \
		and rides.summon("pr_r4", "mount_trench_wyrm"))
	var s3 = rides.water_stamp_for("pr_r4", 5)
	_check("the wyrm's stamp carries its crush rating (+30)", \
		str(s3.get("action", "")) == "swim" and absf(float(s3.get("crush_bonus", 0.0)) - 30.0) < 0.001)
	_check("grant + summon the land mount", rides.grant_mount("pr_r5", "mount_plains_runner") \
		and rides.summon("pr_r5", "mount_plains_runner"))
	var s4 = rides.water_stamp_for("pr_r5", 1)
	_check("wading rides: the land mount stays at the ankles", str(s4.get("action", "")) == "ride")
	var s5 = rides.water_stamp_for("pr_r5", 3)
	_check("a land mount DISMOUNTS at the waterline (the S14.6 law, service-executed)", \
		str(s5.get("action", "")) == "dismount" and rides.active_mount_id("pr_r5").is_empty())
	_check("the dismounted body is back on humanoid limits", \
		absf(float(ac.get_movement_limits("pr_r5").get("max_speed", 0.0)) - 25.0) < 0.01)
	var s6 = rides.water_stamp_for("pr_nobody", 5)
	_check("no mount: 'none' (the naked-swimmer paths run unchanged)", \
		str(s6.get("action", "")) == "none")

	# ---- E. Space-ready + revoke -------------------------------------------------------
	_check("MountKind.SPACE exists (space mounts ride the same path)", \
		int(MDS.MountKind.SPACE) == 3)
	_check("revoke removes ownership and dismisses", \
		rides.revoke_mount("pr_r1", "mount_storm_lancer") \
		and not rides.owns_mount("pr_r1", "mount_storm_lancer") \
		and rides.active_mount_id("pr_r1").is_empty())

	print("probe_riding: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
