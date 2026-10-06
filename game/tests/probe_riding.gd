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
#      The first space mount (the Vesper) loads, rides its OWN lunar
#      profile (the kind default points there too), stamps the
#      anticheat, wades and dismounts at the waterline, does not bail,
#      and its summon is announced through the typed a11y pipeline.
#   F. The GM door: the Skywarden is GM-sourced and fail-closed for
#      non-wardens; a warden's world entry auto-answers the whistle.
#   G. The cliff law: ground mounts BAIL past the glider deploy gate
#      (the S12 law, service-executed); sky mounts fly; hops stay
#      rides; no mount is "none".
#   H. The level gate: a known rider must meet the mount's
#      required_level; unknown service-level riders are trusted.
#
# Script mode: autoloads resolved at runtime (RideService,
# AntiCheatService, DataService).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

var _voice: Dictionary = {}   # the vesper's last typed announcement

func _on_voice(entity_id: String, notification: Dictionary) -> void:
	if entity_id == "pr_sp":
		_voice = notification

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
	var ns = root.get_node_or_null("NotificationService")
	_check("RideService present", rides != null)
	_check("AntiCheatService present", ac != null)
	_check("DataService present", ds != null)
	_check("NotificationService present (the typed pipeline)", ns != null)
	if rides == null or ac == null or ds == null or ns == null:
		quit(1)
		return
	var MDS: GDScript = load("res://core/schemas/mount_data.gd")
	var NK: GDScript = load("res://core/notifications/notification_kind.gd")
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

	# ---- E. Space-ready: the first space mount + revoke -------------------------------
	_check("MountKind.SPACE exists (space mounts ride the same path)", \
		int(MDS.MountKind.SPACE) == 3)
	var vesper = ds.get_mount("mount_vesper_whale")
	_check("the first space mount loads: SPACE kind, filename == id, EVENT, level 60, soulbound", \
		vesper != null and str(vesper.id) == "mount_vesper_whale" \
		and vesper.kind == MDS.MountKind.SPACE \
		and int(vesper.source) == int(MDS.MountSource.EVENT) \
		and int(vesper.required_level) == 60 and int(vesper.cost) == 0 \
		and bool(vesper.soulbound))
	var vprof = ds.get_mount_movement_profile(vesper)
	_check("the vesper's profile resolves through the one path (explicit movement_lunar wins)", \
		vprof != null and str(vprof.id) == "movement_lunar")
	_check("the lunar profile owns the gravity: gentle 2.5, terminal 40, floaty air, a vast turn", \
		absf(float(vprof.gravity_force) - 2.5) < 0.001 \
		and absf(float(vprof.terminal_fall_speed) - 40.0) < 0.001 \
		and absf(float(vprof.air_control) - 1.0) < 0.001 \
		and absf(float(vprof.turn_grip) - 0.6) < 0.001)
	var vblank = vesper.duplicate()
	vblank.movement_profile_id = ""
	var vdef = ds.get_mount_movement_profile(vblank)
	_check("the kind default now points at the lunar class (sec 5's 'its own class' promise)", \
		vdef != null and str(vdef.id) == "movement_lunar")
	ns.notification_sent.connect(_on_voice)
	_check("grant + summon the vesper (an unknown rider stays a trusted service-level caller)", \
		rides.grant_mount("pr_sp", "mount_vesper_whale") \
		and rides.summon("pr_sp", "mount_vesper_whale") \
		and rides.active_mount_id("pr_sp") == "mount_vesper_whale")
	_check("the rider is told through the typed pipeline: MOUNT_SUMMONED -> INFO, addressed to the rider", \
		str(_voice.get("message", "")) == "You summon the Vesper" \
		and int(_voice.get("type", -1)) == int(ns.NotificationType.INFO) \
		and int(_voice.get("data", {}).get("kind", -1)) == int(NK.NotifKind.MOUNT_SUMMONED))
	_check("the space body stamps by its own profile (24 m/s sprint = 60 ceiling)", \
		absf(float(ac.get_movement_limits("pr_sp").get("max_speed", 0.0)) - 60.0) < 0.01)
	var sp1 = rides.water_stamp_for("pr_sp", 1)
	_check("space wades: the vesper rides at the ankles", str(sp1.get("action", "")) == "ride")
	var sp2 = rides.water_stamp_for("pr_sp", 3)
	_check("space is not a swimmer: the vesper is dismissed at the waterline", \
		str(sp2.get("action", "")) == "dismount" and rides.active_mount_id("pr_sp").is_empty())
	_check("summon again for the fall", rides.summon("pr_sp", "mount_vesper_whale"))
	var sp3 = rides.fall_stamp_for("pr_sp", true, 99.0)
	_check("space does not bail: the vesper remembers the way down (no bail, still active)", \
		str(sp3.get("action", "")) == "ride" and not rides.active_mount_id("pr_sp").is_empty())
	_check("revoke removes ownership and dismisses", \
		rides.revoke_mount("pr_r1", "mount_storm_lancer") \
		and not rides.owns_mount("pr_r1", "mount_storm_lancer") \
		and rides.active_mount_id("pr_r1").is_empty())

	# ---- F. The GM door: the Skywarden ---------------------------------------
	var warden = ds.get_mount("mount_gm_skywarden")
	_check("the Skywarden loads: FLYING, GM-sourced, level 1, cost 0, soulbound", \
		warden != null and str(warden.id) == "mount_gm_skywarden" \
		and warden.kind == MDS.MountKind.FLYING \
		and int(warden.source) == int(MDS.MountSource.GM) \
		and int(warden.required_level) == 1 and int(warden.cost) == 0 \
		and bool(warden.soulbound))
	var wprof = ds.get_mount_movement_profile(warden)
	_check("the Skywarden's profile resolves through the one path (movement_gm_sky)", \
		wprof != null and str(wprof.id) == "movement_gm_sky")
	_check("the GM door is fail-closed: an unknown rider is not granted the Skywarden", \
		not rides.grant_mount("pr_gm_nobody", "mount_gm_skywarden"))
	var CDS: GDScript = load("res://core/schemas/character_data.gd")
	var gm = root.get_node_or_null("GameManager")
	_check("GameManager present (the world-entry hook)", gm != null)
	if gm != null:
		var wcd = CDS.new("human", "gm_human", "Warden Test")
		gm.notify_player_entered_world("pr_gm", wcd)
		_check("a warden enters the world and the Skywarden answers (auto-grant)", \
			rides.owns_mount("pr_gm", "mount_gm_skywarden"))
		_check("the warden summons at level 1 (the mount's own law)", \
			rides.summon("pr_gm", "mount_gm_skywarden"))
		var ncd = CDS.new("human", "human_warrior", "Plain Test")
		gm.notify_player_entered_world("pr_plain", ncd)
		_check("a non-warden's world entry grants nothing", \
			not rides.owns_mount("pr_plain", "mount_gm_skywarden"))

	# ---- G. The cliff law ------------------------------------------------------
	_check("bails_on_fall is the ground kind's law (runner bails, lancer and ray do not)", \
		ds.get_mount("mount_plains_runner").bails_on_fall() \
		and not lancer.bails_on_fall() and not ds.get_mount("mount_pearl_ray").bails_on_fall())
	_check("the plains rider still owns the runner (a dismount kept ownership)", \
		rides.owns_mount("pr_r5", "mount_plains_runner"))
	_check("summon for the cliff", rides.summon("pr_r5", "mount_plains_runner"))
	var f1 = rides.fall_stamp_for("pr_r5", true, 12.0)
	_check("the cliff law: a falling land mount BAILS past the glider gate", \
		str(f1.get("action", "")) == "bail" and rides.active_mount_id("pr_r5").is_empty())
	_check("the bailed body is back on humanoid limits", \
		absf(float(ac.get_movement_limits("pr_r5").get("max_speed", 0.0)) - 25.0) < 0.01)
	_check("summon again for the hop", rides.summon("pr_r5", "mount_plains_runner"))
	var f2 = rides.fall_stamp_for("pr_r5", true, 3.0)
	_check("hops stay rides: falling below the deploy gate is not a bail", \
		str(f2.get("action", "")) == "ride")
	_check("re-grant the lancer (revoked in E)", rides.grant_mount("pr_r1", "mount_storm_lancer") \
		and rides.summon("pr_r1", "mount_storm_lancer"))
	var f3 = rides.fall_stamp_for("pr_r1", true, 50.0)
	_check("sky mounts fly: the lancer carries the fall (no bail)", \
		str(f3.get("action", "")) == "ride" and not rides.active_mount_id("pr_r1").is_empty())
	var f4 = rides.fall_stamp_for("pr_nobody", true, 99.0)
	_check("no mount: the cliff law is 'none'", str(f4.get("action", "")) == "none")

	# ---- H. The level gate -------------------------------------------------------
	var lowcd = CDS.new("human", "human_warrior", "Low Rider")
	lowcd.level = 10
	if gm != null:
		gm.notify_player_entered_world("pr_low", lowcd)
	_check("grant is not level-gated (acquisition law lives in the source)", \
		rides.grant_mount("pr_low", "mount_storm_lancer"))
	_check("the level gate closes: level 10 cannot summon the lancer", \
		not rides.summon("pr_low", "mount_storm_lancer"))
	var okcd = CDS.new("human", "human_warrior", "True Rider")
	okcd.level = 50
	if gm != null:
		gm.notify_player_entered_world("pr_ok", okcd)
	_check("the level gate opens at the mount's law: level 50 summons the lancer", \
		rides.grant_mount("pr_ok", "mount_storm_lancer") \
		and rides.summon("pr_ok", "mount_storm_lancer"))
	var splow = CDS.new("human", "human_warrior", "Dark Rider")
	splow.level = 59
	if gm != null:
		gm.notify_player_entered_world("pr_sp_low", splow)
	_check("the level gate holds for space: level 59 waits at the dark", \
		rides.grant_mount("pr_sp_low", "mount_vesper_whale") \
		and not rides.summon("pr_sp_low", "mount_vesper_whale"))
	var spok = CDS.new("human", "human_warrior", "Deep Rider")
	spok.level = 60
	if gm != null:
		gm.notify_player_entered_world("pr_sp_ok", spok)
	_check("the level gate opens: level 60 rides the dark", \
		rides.grant_mount("pr_sp_ok", "mount_vesper_whale") \
		and rides.summon("pr_sp_ok", "mount_vesper_whale"))

	print("probe_riding: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
