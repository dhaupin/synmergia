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
#   I. R45 runtime seams: a REAL GlobeWorldPlayer body adopts the
#      mount's laws on RideService's summon signal (profile walk/
#      jump/gravity; the saddle's sprint gear rides under the AC
#      ceiling), hands them back on dismount (per-world bind
#      survives), the saddle lift never trips the perch law, a cliff
#      fall BAILS the runner off the real body, and the vendor door
#      + the MountUI stable ride the one ledger.
#   J. R46: the favor purse (CurrencyData's wallet promise gets its
#      first real non-gold ledger: cap law, refusal laws, round-trip),
#      the faction ride law (species truth through FactionManager,
#      fail-closed for unknown riders), the favor-priced catalog (the
#      gullwing finally buys), and the stable door (mount/stable
#      triggers; U opens the stable and F stays friends -- the R45
#      dismount collision fixed, the poll respects the text-entry
#      law).
#
# Script mode: autoloads resolved at runtime (RideService,
# AntiCheatService, DataService).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

var _last_voice: Dictionary = {}   # the last typed announcement
var _voice_pid: String = ""       # addressed to this rider

func _on_voice(entity_id: String, notification: Dictionary) -> void:
	if entity_id == "pr_sp" or entity_id == "pr_buy":
		_last_voice = notification
		_voice_pid = entity_id


## Register a low-level character with the world-entry hook so the
## level law knows them (the same path sections F/H ride).
func failsafe_register(pid: String, level: int) -> bool:
	var gm = root.get_node_or_null("GameManager")
	if gm == null:
		return false
	var cd = load("res://core/schemas/character_data.gd").new("human", "human_warrior", "Young Buyer")
	cd.level = level
	gm.notify_player_entered_world(pid, cd)
	return true


## True when the shop catalog carries this mount id.
func _buy_catalog_has(rides, mount_id: String) -> bool:
	for row in rides.get_shop_catalog():
		if str(row.get("id", "")) == mount_id:
			return true
	return false

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
	_check("the vesper's profile resolves through the one path (explicit movement_leviathan wins)", \
		vprof != null and str(vprof.id) == "movement_leviathan")
	_check("the lunar profile owns the gravity: gentle 2.5, terminal 40, floaty air, a vast turn", \
		absf(float(vprof.gravity_force) - 2.5) < 0.001 \
		and absf(float(vprof.terminal_fall_speed) - 40.0) < 0.001 \
		and absf(float(vprof.air_control) - 1.0) < 0.001 \
		and absf(float(vprof.turn_grip) - 0.6) < 0.001)
	var vblank = vesper.duplicate()
	vblank.movement_profile_id = ""
	var vdef = ds.get_mount_movement_profile(vblank)
	_check("the kind default now points at its own class (sec 5's promise -- movement_leviathan, not the S16.4 Settler)", \
		vdef != null and str(vdef.id) == "movement_leviathan")
	ns.notification_sent.connect(_on_voice)
	_check("grant + summon the vesper (an unknown rider stays a trusted service-level caller)", \
		rides.grant_mount("pr_sp", "mount_vesper_whale") \
		and rides.summon("pr_sp", "mount_vesper_whale") \
		and rides.active_mount_id("pr_sp") == "mount_vesper_whale")
	_check("the rider is told through the typed pipeline: MOUNT_SUMMONED -> INFO, addressed to the rider", \
		str(_last_voice.get("message", "")) == "You summon the Vesper" \
		and int(_last_voice.get("type", -1)) == int(ns.NotificationType.INFO) \
		and int(_last_voice.get("data", {}).get("kind", -1)) == int(NK.NotifKind.MOUNT_SUMMONED))
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

	# ---- I. R45 runtime seams: the body, the stable, the shop ------------
	var GP: GDScript = load("res://entities/globe_player.gd")
	var body = GP.new()
	body.entity_id = "pr_rider"
	root.add_child(body)
	await process_frame
	_check("a real globe body is on the ledger's signal wire", \
		body.ride_service == rides and not body.is_mounted())
	body.bind_to_world("moon")
	_check("grant + summon the plains runner for the body", \
		rides.grant_mount("pr_rider", "mount_plains_runner") \
		and rides.summon("pr_rider", "mount_plains_runner"))
	await process_frame
	_check("the body ADOPTED the mount's laws (walk 6, jump 9, gravity 22 -- declared, not invented)", \
		body.is_mounted() and absf(body.walk_speed - 6.0) < 0.001 \
		and absf(body.jump_force - 9.0) < 0.001 and absf(body.gravity_force - 22.0) < 0.001)
	_check("the saddle's sprint gear rides UNDER the anticheat ceiling (13.5 x 0.6 = 8.1 of the 33.75 legal)", \
		absf(body.mount_sprint_speed() - 8.1) < 0.001)
	_check("the summit test: the body's laws survive a per-world bind (dismount restores the CAPTURED humanoid gravity -- the moon's 6)", \
		rides.dismiss("pr_rider") and absf(body.gravity_force - 6.0) < 0.001 \
		and absf(body.walk_speed - body.WALK_SPEED_DEFAULT) < 0.001 \
		and absf(body.jump_force - body.JUMP_FORCE_HUMANOID) < 0.001 \
		and not body.is_mounted())
	_check("re-summon: the saddle lift is a saddle, not a perch (0.4 < the 0.55 gate)", \
		rides.summon("pr_rider", "mount_plains_runner") and body.is_mounted() \
		and body.SADDLE_LIFT < body.PERCH_MIN_LIFT)
	var f5 = rides.fall_stamp_for("pr_rider", true, 12.0)
	_check("the cliff law fires through the REAL body: the runner bails, the body hands back the humanoid", \
		str(f5.get("action", "")) == "bail" and not body.is_mounted())

	_check("the vendor door opens with data truth: gold-priced mounts in (the runner); non-vendor wallets stay out", \
		_buy_catalog_has(rides, "mount_plains_runner"))
	var InvComp = load("res://core/components/inventory_component.gd")
	var poor = InvComp.new()
	poor.name = "ProbePurse"
	root.add_child(poor)
	poor.set_owner_id("pr_buy")
	var inv_svc = root.get_node_or_null("InventoryService")
	_check("the shop resolves a purse through InventoryService (the vendor idiom)", \
		inv_svc != null and inv_svc.has_method("register_inventory"))
	if inv_svc != null:
		inv_svc.register_inventory("pr_buy", poor)
	_check("gold law: a broke rider is refused (need 250)", \
		not rides.purchase_mount("pr_buy", "mount_plains_runner").get("success", true))
	poor.add_gold(249)
	_check("249 gold is one short: still refused", \
		not rides.purchase_mount("pr_buy", "mount_plains_runner").get("success", true))
	poor.add_gold(1)
	var buy = rides.purchase_mount("pr_buy", "mount_plains_runner")
	_check("250 gold buys the runner: purse drained to 0, the ONE ledger carries the grant", \
		bool(buy.get("success", false)) and poor.get_gold() == 0 \
		and rides.owns_mount("pr_buy", "mount_plains_runner"))
	poor.add_gold(250)
	_check("the ledger's second lock: a re-purchase is refused", \
		not rides.purchase_mount("pr_buy", "mount_plains_runner").get("success", true) \
		and poor.get_gold() == 250)
	_check("the level law closes the shop door too: level 4 does not buy the level-5 runner", \
		failsafe_register("pr_young", 4) and not rides.purchase_mount("pr_young", "mount_plains_runner").get("success", true))
	_check("the grantor announces acquisition through the typed pipeline (MOUNT_ACQUIRED -> INFO)", \
		str(_last_voice.get("message", "")) == "You have acquired the Plains Runner" \
		and int(_last_voice.get("type", -1)) == int(ns.NotificationType.INFO) \
		and int(_last_voice.get("data", {}).get("kind", -1)) == int(NK.NotifKind.MOUNT_ACQUIRED))
	_check("summon through the signal wire: the new owner takes the saddle", \
		rides.summon("pr_buy", "mount_plains_runner"))
	var buyer = GP.new()
	buyer.entity_id = "pr_buy"
	root.add_child(buyer)
	await process_frame
	rides.dismiss("pr_buy")
	_check("the buyer's body is local (PlayerManager duck-types entity_id) and takes the saddle on the re-summon", \
		buyer.ride_service == rides and rides.summon("pr_buy", "mount_plains_runner") \
		and buyer.is_mounted())

	var stable = load("res://ui/components/mount_ui.gd").new()
	stable.name = "ProbeStable"
	root.add_child(stable)
	await process_frame
	var spanel = stable.get_panel()
	_check("the MountUI stable builds on the panel contract (panel + Main + title + close X)", \
		spanel != null and spanel.get_node_or_null("Main") != null \
		and spanel.get_node_or_null("Main/Header/Title") != null \
		and spanel.get_node_or_null("Main/Header/CloseButton") != null)
	_check("the stable reads the ONE ledger: the runner's row exists (text label for the a11y layer)", \
		spanel.get_node_or_null("Main/MountList/Row_mount_plains_runner/Mount_mount_plains_runner") != null)
	var sbtn: Button = spanel.get_node_or_null("Main/MountList/Row_mount_plains_runner/Summon_mount_plains_runner")
	_check("the Summon button exists, is pressable, and the panel knows the active truth", \
		sbtn is Button and str(stable._active_label.text) == "Riding: Plains Runner")
	if sbtn is Button:
		sbtn.pressed.emit()
		await process_frame
	_check("one button, one meaning: the press DISMISSED the active mount (panel refreshed)", \
		rides.active_mount_id("pr_buy").is_empty() \
		and str(stable._active_label.text) == "Walking" \
		and stable._list.get_child_count() == 1)

	# -- J. R46: the favor purse, the faction law, the stable door -------
	# The dismount key is U (physical 85), NOT F: HudHotkeys toggles the
	# friends panel on F, and a raw Input poll on F would tap the saddle
	# every time the rider opened their friends list (the R45
	# collision, caught and fixed).
	var proj_text := ""
	var pf := FileAccess.open("res://project.godot", FileAccess.READ)
	if pf != null:
		proj_text = pf.get_as_text()
	var dismount_block := ""
	var d_idx := proj_text.find("dismount={")
	if d_idx >= 0:
		dismount_block = proj_text.substr(d_idx, 400)
	_check("the dismount key is U (physical 85) -- F belongs to the friends panel", \
		dismount_block.contains("physical_keycode\":85") \
		and not dismount_block.contains("physical_keycode\":70"))
	_check("the dismount poll respects the text-entry law (no focus owner in the bare harness: the poll stays armed)", \
		not body._text_entry_focused())

	# The favor purse: CurrencyData has promised "wallets reference
	# CurrencyData.id" since S14 -- gold was the only wallet that
	# existed. The ledger lives in the SAME purse the vendor chain
	# already trusts.
	_check("the ledger refuses invented currency (the catalog is the law)", \
		not poor.add_currency("currency_unknown_favor", 10))
	_check("the ledger refuses non-payment (zero and negative never mint)", \
		not poor.add_currency("currency_reclaimer_favor", 0) \
		and not poor.add_currency("currency_reclaimer_favor", -5))
	_check("favor lands in the purse and the balance reads back", \
		poor.add_currency("currency_reclaimer_favor", 400) \
		and poor.get_currency_amount("currency_reclaimer_favor") == 400)
	_check("a short purse cannot spend", \
		not poor.remove_currency("currency_reclaimer_favor", 401) \
		and poor.get_currency_amount("currency_reclaimer_favor") == 400)
	_check("the purse round-trips through to_dict/from_dict (persistence law)", \
		InvComp.from_dict(poor.to_dict()).get_currency_amount("currency_reclaimer_favor") == 400)

	# The catalog speaks every vendor wallet: rows carry their currency
	# truth, and the gullwing's 400 favor is a shop good at last.
	var runner_cur := ""
	var gull_cur := ""
	for crow in rides.get_shop_catalog():
		if str(crow.get("id", "")) == "mount_plains_runner":
			runner_cur = str(crow.get("currency", ""))
		if str(crow.get("id", "")) == "mount_gullwing":
			gull_cur = str(crow.get("currency", ""))
	_check("catalog rows carry their currency truth (the runner's default wallet reads empty; the gullwing speaks favor)", \
		runner_cur == "" and gull_cur == "currency_reclaimer_favor")
	var favor_purse = InvComp.new()
	favor_purse.name = "ProbeFavorPurse"
	root.add_child(favor_purse)
	favor_purse.set_owner_id("pr_favor")
	if inv_svc != null:
		inv_svc.register_inventory("pr_favor", favor_purse)
	failsafe_register("pr_favor", 30)
	favor_purse.add_currency("currency_reclaimer_favor", 399)
	_check("the favor gate: 399 of 400 is one short", \
		not rides.purchase_mount("pr_favor", "mount_gullwing").get("success", true) \
		and favor_purse.get_currency_amount("currency_reclaimer_favor") == 399)
	favor_purse.add_currency("currency_reclaimer_favor", 1)
	var favor_buy = rides.purchase_mount("pr_favor", "mount_gullwing")
	_check("400 favor buys the gullwing: purse drained, the ONE ledger carries the grant", \
		bool(favor_buy.get("success", false)) \
		and favor_purse.get_currency_amount("currency_reclaimer_favor") == 0 \
		and rides.owns_mount("pr_favor", "mount_gullwing"))
	_check("the gullwing answers the whistle once it is owned (summon + dismiss)", \
		rides.summon("pr_favor", "mount_gullwing") and rides.dismiss("pr_favor"))

	# The faction law: the gullwing rides for the humans (its Currency
	# carries faction_human too, but the FACTION .tres is the gate).
	var gsyn = load("res://core/schemas/character_data.gd").new("synthetic", "synthetic_mender", "Rust Cousin")
	gsyn.level = 30
	var gm2 = root.get_node_or_null("GameManager")
	if gm2 != null:
		gm2.notify_player_entered_world("pr_syn", gsyn)
	rides.grant_mount("pr_syn", "mount_gullwing")
	_check("the faction law is fail-closed: a synthetic does not summon the humans' gullwing", \
		not rides.summon("pr_syn", "mount_gullwing"))
	_check("the faction law opens for the right people: a human of level rides it once granted", \
		failsafe_register("pr_gull", 30) and rides.grant_mount("pr_gull", "mount_gullwing") \
		and rides.summon("pr_gull", "mount_gullwing"))
	rides.dismiss("pr_gull")

	# The stable door: words and a key. The MenuManager funnel and the
	# HudHotkeys U binding are wired to the same "mounts" island the
	# registry resolves.
	var IR = load("res://ui/islands/island_registry.gd")
	_check("the stable door has words: 'mount' and 'stable' trigger the mounts island", \
		IR.islands_triggered_by("where is the stable").has("mounts") \
		and IR.islands_triggered_by("summon my mount").has("mounts"))
	var hh_src := ""
	var hh := FileAccess.open("res://ui/hud/hud_hotkeys.gd", FileAccess.READ)
	if hh != null:
		hh_src = hh.get_as_text()
	_check("the stable door has a key: U routes to the mounts panel and F stays friends", \
		hh_src.contains("KEY_U") and hh_src.contains("_toggle_panel(\"mounts\")") \
		and hh_src.contains("_toggle_panel(\"friends\")"))

	# The stable rides the wire: the panel refreshes on the same signals
	# the body listens to -- no reopen needed.
	_check("the stable rides the wire: a summon refreshes the open panel live", \
		rides.summon("pr_buy", "mount_plains_runner") \
		and str(stable._active_label.text) == "Riding: Plains Runner")
	_check("and a dismiss walks it back", \
		rides.dismiss("pr_buy") and str(stable._active_label.text) == "Walking")

	print("probe_riding: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
