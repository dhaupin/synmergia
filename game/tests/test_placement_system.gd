## Placement + housing integration tests.
## Covers the shared ownership-scope interface (PlacementAccess) as used
## by ankhs (bind gating), guards (personal-mode targeting), and
## HousingService (plots, purchase, placement costs/ownership).
## Test scripts must load() services at runtime -- parse-time preloads
## of autoload-referencing scripts poison script-mode compilation.
extends SceneTree

var _passed := 0
var _failed := 0

var _pa: GDScript = null
var _ankh: GDScript = null
var _housing: GDScript = null
var _guard_data: GDScript = null
var _guard_ai: GDScript = null
var _guard: GDScript = null


func _initialize() -> void:
	await process_frame
	_pa = load("res://core/schemas/placement_access.gd")
	_ankh = load("res://core/schemas/ankh.gd")
	_housing = load("res://core/services/housing_service.gd")
	_guard_data = load("res://core/schemas/guard_data.gd")
	_guard_ai = load("res://core/ai/guard_ai.gd")
	_guard = load("res://entities/guard.gd")
	_test_access_scopes()
	_test_access_deny_and_builders()
	_test_ankh_bind_scoping()
	_test_ankh_faction_check_uses_faction_id()
	_test_plot_registration_and_lookup()
	_test_plot_purchase_flows()
	_test_placement_costs_and_ownership()
	_test_placed_guard_is_personal_and_friendly_to_owner()
	_test_placed_ankh_scope_stamped()
	_test_guardai_personal_targeting()
	print("Placement tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# --- helpers ---------------------------------------------------------------

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: %s" % msg)
		print("FAIL: %s" % msg)


## Player stub plus the guild surface (no Entity carries guild fields;
## real guild identity resolves via GuildService, so stubs declare it).
## Built via set_script at runtime: an inner class `extends` of the stub
## is a parse-time load of entity.gd (which references the EventHub
## autoload) and poisons script-mode compilation -- the same boot-order
## poison documented in test_hit_table.gd.
func _mk_player(id: String, props: Dictionary = {}):
	var p = load("res://tests/support/reward_player_stub.gd").new()
	p.set_script(load("res://tests/support/guild_player_stub.gd"))
	p.entity_id = id
	p.display_name = id
	for key in props:
		p.set(key, props[key])
	root.add_child(p)
	return p


func _free(node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()


# --- PlacementAccess ---------------------------------------------------------

func _test_access_scopes() -> void:
	var world = _pa.world()
	_assert(world.evaluate(_mk_player("anyone")), "WORLD admits everyone")
	var personal = _pa.personal("owner_1", ["friend_1"])
	_assert(personal.evaluate(_mk_player("owner_1")), "owner passes PERSONAL")
	_assert(personal.evaluate(_mk_player("friend_1")), "allowed_id passes PERSONAL")
	_assert(not personal.evaluate(_mk_player("stranger")), "stranger denied PERSONAL")
	var guild = _pa.guild("g_aurora")
	_assert(guild.evaluate(_mk_player("m1", {"guild_id": "g_aurora"})), "same-guild member passes GUILD")
	_assert(not guild.evaluate(_mk_player("m2", {"guild_id": "g_other"})), "other-guild member denied GUILD")
	_assert(not guild.evaluate(_mk_player("m3")), "guildless player denied GUILD")
	var faction = _pa.faction("town")
	_assert(faction.evaluate(_mk_player("f1", {"faction_id": "town"})), "same-faction member passes FACTION")
	_assert(not faction.evaluate(_mk_player("f2", {"faction_id": "horde"})), "other-faction member denied FACTION")


func _test_access_deny_and_builders() -> void:
	var banned_public = _pa.world()
	banned_public.deny_ids = ["griefer"]
	_assert(not banned_public.evaluate(_mk_player("griefer")), "deny beats WORLD scope")
	var banned_owner = _pa.personal("owner_1")
	banned_owner.deny_ids = ["friend_1"]
	banned_owner.allowed_ids = ["friend_1"]
	_assert(not banned_owner.evaluate(_mk_player("friend_1")), "deny beats allowed_ids")
	_assert(_pa.personal("o").evaluate(_mk_player("o")), "owner passes with empty allowed list")


# --- Ankh bind scoping -------------------------------------------------------

func _test_ankh_bind_scoping() -> void:
	var ankh = _ankh.new()
	ankh.ankh_id = "ankh_test_personal"
	root.add_child(ankh)
	ankh.access = _pa.personal("owner_1", ["friend_1"])
	_assert(not ankh.can_bind(_mk_player("stranger")), "stranger cannot bind personal ankh")
	_assert(ankh.describe_bind_denial(_mk_player("stranger")) == "not_allowed", "denial reason is not_allowed")
	_assert(ankh.can_bind(_mk_player("owner_1")), "owner can bind personal ankh")
	_assert(ankh.can_bind(_mk_player("friend_1")), "allowed player can bind personal ankh")

	var guild_ankh = _ankh.new()
	guild_ankh.ankh_id = "ankh_test_guild"
	root.add_child(guild_ankh)
	guild_ankh.ankh_type = _ankh.AnkhType.GUILD
	guild_ankh.required_guild_id = "g_aurora"
	_assert(not guild_ankh.can_bind(_mk_player("m2", {"guild_id": "g_other", "guild_rank": 5})), "wrong guild cannot bind GUILD ankh")
	# required_guild_rank 0 means "any rank"; the m1 stubs default to rank 0.
	_assert(guild_ankh.can_bind(_mk_player("m1", {"guild_id": "g_aurora"})), "right guild with any rank (0) can bind GUILD ankh")
	guild_ankh.required_guild_rank = 2
	_assert(not guild_ankh.can_bind(_mk_player("m1", {"guild_id": "g_aurora", "guild_rank": 1})), "right guild but rank below requirement denied")
	_assert(guild_ankh.can_bind(_mk_player("m1", {"guild_id": "g_aurora", "guild_rank": 2})), "right guild + sufficient rank can bind GUILD ankh")
	_free(ankh)
	_free(guild_ankh)


func _test_ankh_faction_check_uses_faction_id() -> void:
	var ankh = _ankh.new()
	ankh.ankh_id = "ankh_test_faction"
	root.add_child(ankh)
	ankh.required_faction = "town"
	# Regression: can_bind read player.faction (never exists on Entity);
	# Entity carries faction_id. Both are accepted now.
	_assert(ankh.can_bind(_mk_player("f1", {"faction_id": "town"})), "faction_id (Entity field) accepted")
	_assert(not ankh.can_bind(_mk_player("f2", {"faction_id": "horde"})), "wrong faction_id denied")
	_assert(ankh.describe_bind_denial(_mk_player("f2", {"faction_id": "horde"})) == "faction", "denial reason is faction")
	_free(ankh)


# --- HousingService: plots + purchase --------------------------------------

func _mk_housing() -> Node:
	var svc = _housing.new()
	root.add_child(svc)
	return svc


func _test_plot_registration_and_lookup() -> void:
	var svc = _mk_housing()
	svc.register_plot("plot_a", "test_zone", Vector3(0, 0, 0), 10.0, 50000)
	svc.register_plot("plot_b", "test_zone", Vector3(100, 0, 100), 10.0, 60000)
	_assert(not svc.get_plot("plot_a").is_empty(), "registered plot is retrievable")
	_assert(svc.get_plot("nope").is_empty(), "unknown plot returns empty dict")
	var near = svc.get_nearest_plot(Vector3(1, 0, 1))
	_assert(str(near.get("id", "")) == "plot_a", "nearest plot resolves by radius")
	var none = svc.get_nearest_plot(Vector3(200, 0, 200))
	_assert(none.is_empty(), "position outside all radii finds nothing")
	var unowned = svc.get_nearest_plot(Vector3(1, 0, 1), "unowned")
	_assert(str(unowned.get("id", "")) == "plot_a", "unowned filter matches fresh plot")
	svc.register_test_plot("plot_c", "test_zone", "someone")
	var owned_only = svc.get_nearest_plot(Vector3(1, 0, 1), "owned")
	_assert(str(owned_only.get("id", "")) == "plot_c", "owned filter matches the owned plot only")
	svc.queue_free()


func _test_plot_purchase_flows() -> void:
	var svc = _mk_housing()
	svc.register_plot("plot_p", "test_zone", Vector3.ZERO, 10.0, 50000)
	var rich = _mk_player("buyer", {"gold": 60000})
	var poor = _mk_player("pauper", {"gold": 100})
	var stranger = _mk_player("other")

	var r1: Dictionary = svc.purchase_plot(poor, "plot_p")
	_assert(str(r1.get("reason", "")) == "insufficient_gold", "purchase denied without gold")
	_assert(str(svc.get_plot("plot_p")["owner_id"]) == "", "denied purchase leaves plot unowned")

	var r2: Dictionary = svc.purchase_plot(rich, "plot_p")
	_assert(bool(r2.get("ok", false)), "purchase succeeds with gold")
	_assert(int(rich.gold) == 10000, "gold deducted exactly")
	_assert(str(svc.get_plot("plot_p")["owner_id"]) == "buyer", "ownership recorded")

	var r3: Dictionary = svc.purchase_plot(stranger, "plot_p")
	_assert(str(r3.get("reason", "")) == "already_owned", "owned plot cannot be repurchased")
	var r4: Dictionary = svc.purchase_plot(rich, "plot_p")
	_assert(str(r4.get("reason", "")) == "already_owned", "owner cannot repurchase own plot")

	svc.register_plot("plot_q", "test_zone", Vector3(50, 0, 0), 10.0, 50000)
	var r5: Dictionary = svc.purchase_plot(rich, "plot_q")
	_assert(str(r5.get("reason", "")) == "already_owns_plot", "second plot denied (one per player)")
	_free(rich)
	_free(poor)
	_free(stranger)
	svc.queue_free()


func _test_placement_costs_and_ownership() -> void:
	var svc = _mk_housing()
	svc.register_test_plot("plot_own", "test_zone", "owner_x")
	var outsider = _mk_player("not_owner", {"gold": 999999})
	# 400000 = 250k guard + 100k ankh + 50k headroom.
	var owner_p = _mk_player("owner_x", {"gold": 400000})

	var g = svc.place_house_guard(outsider, "plot_own")
	_assert(g == null, "non-owner cannot place house guard")
	var a = svc.place_personal_ankh(outsider, "plot_own")
	_assert(a == null, "non-owner cannot place personal ankh")

	var g2 = svc.place_house_guard(owner_p, "plot_own")
	_assert(g2 != null, "owner places house guard")
	_assert(int(owner_p.gold) == 400000 - _housing.HOUSE_GUARD_COST, "guard costs 250000 gold")
	var g3 = svc.place_house_guard(owner_p, "plot_own")
	_assert(g3 == null, "second guard denied (one per plot)")
	_assert(str(svc.get_plot("plot_own")["guard_id"]) != "", "guard id recorded on plot")

	var a2 = svc.place_personal_ankh(owner_p, "plot_own")
	_assert(a2 != null, "owner places personal ankh")
	_assert(int(owner_p.gold) == 50000, "guard + ankh cost exactly 350000 gold")
	_assert(str(svc.get_plot("plot_own")["ankh_id"]) != "", "ankh id recorded on plot")
	_free(g2)
	_free(a2)
	_free(outsider)
	_free(owner_p)
	svc.queue_free()


func _test_placed_guard_is_personal_and_friendly_to_owner() -> void:
	var svc = _mk_housing()
	svc.register_test_plot("plot_g", "test_zone", "home_owner")
	var owner_p = _mk_player("home_owner", {"gold": 300000})
	var guard = svc.place_house_guard(owner_p, "plot_g")
	_assert(guard != null, "guard placed for ownership test")
	if guard != null:
		var data = guard.guard_data
		_assert(data != null, "placed guard carries GuardData")
		_assert(str(data.owner_id) == "home_owner", "guard owned by buyer")
		_assert(int(data.guard_duty) == _guard_data.GuardDuty.PERSONAL, "guard duty is PERSONAL")
		_assert(data.access != null, "guard carries PlacementAccess")
		_assert(data.access.evaluate(owner_p), "owner can access own guard's scope")
		_assert(data.allowed_player_ids.has("home_owner"), "owner on allowed list")
		_assert(guard._guard_ai != null, "GuardAI attached at placement")
	_free(owner_p)
	svc.queue_free()


func _test_placed_ankh_scope_stamped() -> void:
	var svc = _mk_housing()
	svc.register_test_plot("plot_a2", "test_zone", "ankh_owner")
	var owner_p = _mk_player("ankh_owner", {"gold": 200000})
	var ankh = svc.place_personal_ankh(owner_p, "plot_a2")
	_assert(ankh != null, "ankh placed for scope test")
	if ankh != null:
		_assert(ankh.access != null, "placed ankh carries PlacementAccess")
		_assert(ankh.access.evaluate(owner_p), "owner can bind own ankh")
		_assert(not ankh.can_bind(_mk_player("random_person")), "stranger cannot bind placed ankh")
		_assert(str(ankh.zone_id) == "test_zone", "ankh zone stamped from plot")
	_free(ankh)
	_free(owner_p)
	svc.queue_free()


# --- GuardAI personal mode ----------------------------------------------------

func _mk_guard_with(data: Resource):
	var guard = _guard.new()
	guard.display_name = "House Guard"
	guard.entity_id = "hg_test"
	root.add_child(guard)
	var ai = _guard_ai.new()
	ai.name = "GuardAI"
	guard.attach_ai(ai)
	guard._guard_ai = ai
	ai.setup(data)
	return guard


func _test_guardai_personal_targeting() -> void:
	# Personal guard: owner + one friend. Trespasser and owner both near.
	var data: Resource = _guard_data.house_guard("hg_x", "House Guard", "boss_1", ["boss_1", "friend_1"])
	data.guard_duty = _guard_data.GuardDuty.PERSONAL
	data.access = _pa.personal("boss_1", ["friend_1"])
	var guard = _mk_guard_with(data)
	var owner_p = _mk_player("boss_1")
	var friend = _mk_player("friend_1")
	var intruder = _mk_player("trespasser_1")
	var ai = guard._guard_ai
	_assert(ai._is_valid_target(intruder), "intruder is a valid target for personal guard")
	_assert(not ai._is_valid_target(owner_p), "owner is never a target (home is safe)")
	_assert(not ai._is_valid_target(friend), "allowed player is never a target")
	_assert(ai.is_criminal(intruder) == false, "intruder is not a CRIMINAL (different mechanism)")
	# Town guard with WORLD access must still fight (scope skip rule).
	var town_data: Resource = _guard_data.town_guard("tg_x", "Town Guard", "haven")
	town_data.access = _pa.world()
	var town_guard = _mk_guard_with(town_data)
	var town_ai = town_guard._guard_ai
	var victim = _mk_player("innocent_1")
	victim.health_component = null
	var crim = _mk_player("town_criminal")
	town_ai.mark_criminal("town_criminal")
	_assert(town_ai._is_valid_target(crim), "town guard still targets criminals with WORLD access")
	_assert(not town_ai._is_valid_target(victim), "town guard ignores innocents with WORLD access")
	_free(guard)
	_free(town_guard)
	_free(owner_p)
	_free(friend)
	_free(intruder)
	_free(victim)
	_free(crim)
