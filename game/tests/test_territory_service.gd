## Territory receipt -- the no-orphan test for the ownership overlay.
##
## Legs:
##   1. DataService loads data/territories and every zone ref resolves.
##   2. TerritoryService indexes zones -> territory, and refuses a zone
##      claimed by two territories.
##   3. The map label reads the controller (Starter Plains -> Human Alliance).
##   4. A guild claim is gated by MANAGE_GVG.
##   5. A faction war contests the territory and peace resolves it.
##   6. FactionData no longer carries the dead controlled_zones array.
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

	# 4. guild claim gated by MANAGE_GVG.
	var gs = root.get_node_or_null("GuildService")
	_check("GuildService autoload present", gs != null)
	if gs:
		gs._guilds["guild_test"] = {
			"id": "guild_test",
			"leader_id": "p1",
			"members": [
				{"id": "p1", "rank": 0},
				{"id": "p2", "rank": 3}
			]
		}
		var claimable = TerritoryData.new()
		claimable.id = "terr_test_claim"
		claimable.display_name = "Claimable"
		var no_zones: Array[String] = []
		claimable.zone_ids = no_zones
		ts.register_territory(claimable)
		_check("officer-rank guild master can claim",
			gs.claim_territory("guild_test", "p1", "terr_test_claim"))
		_check("claim resolves to the guild",
			int(ts.get_territory("terr_test_claim").controller) == TerritoryData.Controller.GUILD
			and str(ts.get_territory("terr_test_claim").controller_id) == "guild_test")
		_check("recruit cannot claim",
			not gs.claim_territory("guild_test", "p2", "terr_test_claim"))

	# 5. war contests and peace resolves.
	var fm = root.get_node_or_null("FactionManager")
	_check("FactionManager autoload present", fm != null)
	if fm:
		# WorldService does this during boot; the receipt loads directly.
		fm.load_factions()
		var declared: bool = fm.declare_war(
			"faction_human", "faction_akkan", "test_attacker", "terr_starter_plains"
		)
		_check("war declaration with a territory succeeds", declared)
		_check("territory is contested during the war", starter.is_contested())
		_check("territory records the war id", str(starter.active_war_id) != "")
		_check("peace ends the contest", fm.end_war("faction_human", "faction_akkan"))
		_check("territory is no longer contested", not starter.is_contested())
		_check("strongest claimant keeps control",
			str(starter.controller_id) == "faction_human")

	# 6. the dead field is gone.
	var faction = ds.get_faction("faction_human")
	_check("FactionData has no controlled_zones field",
		faction != null and not ("controlled_zones" in faction))

	_finish()
