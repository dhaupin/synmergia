## Territory receipt -- the no-orphan test for the ownership overlay.
##
## Legs:
##   1. DataService loads data/territories and every zone ref resolves.
##   2. TerritoryService indexes zones -> territory, and refuses a zone
##      claimed by two territories.
##   3. The map label reads the controller (Starter Plains -> Human Alliance).
##   4. A guild claim is gated by MANAGE_GVG and `/claim` stakes it.
##   5. Claims survive `reload()` through DictStore, and clearing the overlay
##      restores the authored controller.
##   6. `/war` status is readable; declare/end are admin-only; the territory
##      contest rides the same FactionManager war.
##   7. FactionData no longer carries the dead controlled_zones array.
##
## Run:
##   godot --headless --path game --script res://tests/test_territory_service.gd
extends SceneTree

const TerritoryData = preload("res://core/schemas/territory_data.gd")

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
	print("--- TERRITORY: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	var ts = root.get_node_or_null("TerritoryService")
	_check("DataService autoload present", ds != null)
	_check("TerritoryService autoload present", ts != null)
	if ds == null or ts == null:
		_finish()
		return

	# Start from the authored state even if a previous run left an overlay.
	ts.clear_persisted()
	ts.reload()

	# 1. catalog + refs.
	var territories: Array = ds.get_all_territories()
	_check("territory catalog loaded", territories.size() >= 1)
	var zone_ids: Dictionary = {}
	for zone in ds.get_all_zones():
		zone_ids[str(zone.id)] = true
	var bad_zones: Array = []
	for territory in territories:
		for zone_id in territory.zone_ids:
			if not zone_ids.has(str(zone_id)):
				bad_zones.append("%s -> %s" % [territory.id, zone_id])
	_check("all territory zone refs resolve", bad_zones.is_empty())
	if not bad_zones.is_empty():
		print("    phantom zones: ", bad_zones)

	var starter = ts.for_zone("zone_starter_plains")
	_check("starter plains belongs to a territory", starter != null)
	if starter == null:
		_finish()
		return
	_check("starter territory id", str(starter.id) == "terr_starter_plains")
	_check("starter controller is the human faction",
		int(starter.controller) == TerritoryData.Controller.FACTION
		and str(starter.controller_id) == "faction_human")

	# 2. duplicate zone refused.
	var dup = TerritoryData.new()
	dup.id = "terr_test_duplicate"
	dup.display_name = "Duplicate"
	var dup_zones: Array[String] = ["zone_starter_plains"]
	dup.zone_ids = dup_zones
	_check("a zone cannot join two territories", not ts.register_territory(dup))
	_check("rejected duplicate did not enter the registry", ts.get_territory("terr_test_duplicate") == null)

	# 3. map label reads the owner.
	var label: String = ts.zone_label("zone_starter_plains", "Starter Plains")
	_check("zone label names the territory", label.contains("Starter Plains"))
	_check("zone label names the controller", label.contains("Human Alliance"))

	var wm_script = load("res://ui/components/world_map.gd")
	var wm = wm_script.new()
	root.add_child(wm)
	await process_frame
	wm._on_zone_loaded(starter)
	var zone_label: Label = wm.get_node_or_null("Container/ZoneName")
	_check("world map renders the territory label",
		zone_label != null and zone_label.text.contains("Starter Plains"))
	wm.free()

	# 4. guild claim through the player command.
	var gs = root.get_node_or_null("GuildService")
	var chat = root.get_node_or_null("ChatService")
	_check("GuildService autoload present", gs != null)
	_check("ChatService autoload present", chat != null)
	if gs and chat:
		gs._guilds["guild_test"] = {
			"id": "guild_test",
			"name": "Test Guild",
			"leader_id": "p1",
			"members": [
				{"id": "p1", "rank": 0},
				{"id": "p2", "rank": 3}
			]
		}
		gs._player_guilds["p1"] = "guild_test"
		gs._player_guilds["p2"] = "guild_test"

		_check("recruit cannot claim through the guild API",
			not gs.claim_territory("guild_test", "p2", "terr_starter_plains"))
		_check("`/claim` runs for a guild master",
			chat._cmd_claim("p1", ["terr_starter_plains"]))
		starter = ts.for_zone("zone_starter_plains")
		_check("claim stakes a second claimant", starter.claimants.size() == 2)
		_check("a 50-influence claim does not unseat a 100-influence holder",
			str(starter.controller_id) == "faction_human" and starter.is_contested())

		# 5. reboot round-trip: reload rebuilds data then re-applies the overlay.
		ts.reload()
		starter = ts.for_zone("zone_starter_plains")
		_check("claim survives a reload", starter.claimants.size() == 2 and starter.is_contested())
		ts.clear_persisted("terr_starter_plains")
		ts.reload()
		starter = ts.for_zone("zone_starter_plains")
		_check("clearing the overlay restores the authored controller",
			str(starter.controller_id) == "faction_human" and not starter.is_contested())

	# 6. war command surface.
	var fm = root.get_node_or_null("FactionManager")
	var pm = root.get_node_or_null("PermissionManager")
	_check("FactionManager autoload present", fm != null)
	_check("PermissionManager autoload present", pm != null)
	if fm and pm and chat:
		fm.load_factions()
		_check("`/war` status is readable by players", chat._cmd_war("p1", []))
		_check("non-admin `/war declare` is refused",
			chat._cmd_war("p1", ["declare", "faction_human", "faction_akkan", "terr_starter_plains"])
			and not fm.is_at_war("faction_human", "faction_akkan"))

		# Grant the test operator a cached ADMIN level, then use the command.
		pm._validation_cache["admin"] = {
			"time": Time.get_ticks_msec(),
			"level": 100
		}
		_check("admin `/war declare` runs",
			chat._cmd_war("admin", ["declare", "faction_human", "faction_akkan", "terr_starter_plains"]))
		starter = ts.for_zone("zone_starter_plains")
		_check("war command contests the territory", starter.is_contested())
		_check("war command records the war id", str(starter.active_war_id) != "")

		# War overlay survives a reload too.
		ts.reload()
		starter = ts.for_zone("zone_starter_plains")
		_check("war survives a reload", str(starter.active_war_id) != "")

		_check("admin `/war end` runs",
			chat._cmd_war("admin", ["end", "faction_human", "faction_akkan"]))
		starter = ts.for_zone("zone_starter_plains")
		_check("peace clears the contest and keeps the strongest claim",
			not starter.is_contested() and str(starter.controller_id) == "faction_human")
		pm._validation_cache.erase("admin")

	# 7. the dead field is gone.
	var faction = ds.get_faction("faction_human")
	_check("FactionData has no controlled_zones field",
		faction != null and not ("controlled_zones" in faction))

	# Leave no runtime overlay or fake guild behind.
	ts.clear_persisted()
	ts.reload()
	if gs:
		gs._guilds.erase("guild_test")
		gs._player_guilds.erase("p1")
		gs._player_guilds.erase("p2")
	_finish()
