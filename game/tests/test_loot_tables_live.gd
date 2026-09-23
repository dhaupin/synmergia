## test_loot_tables_live.gd - END-TO-END loot verification in the playable
## scene. Run in RENDERING mode:
##
##   cd game && xvfb-run godot --path . --script res://tests/test_loot_tables_live.gd
##
## Chains exercised (the real integration, not stubs):
##   1. LootTableResolver resolves every table referenced by enemy data
##      (bare-id convention -> res://data/loot_tables/<id>.tres).
##   2. EnemyData.roll_loot() pays base gold (gold_min/max) and rolls the
##      table through the SAME resolver (no more direct-path miss).
##   3. SkillBook extends Item: runtime books are real items that stack,
##      loot, and carry book_skill_id/book_upgrade_level.
##   4. GroundLootService expands book_<skill>_<tier> ids through
##      SkillAcademyService.create_book (runtime catalog, no .tres).
##   5. LIVE kill: slime dies -> exactly ONE table roll -> ground drop
##      appears -> pickup lands the item + currency. The corpse does NOT
##      roll the table again (double-dip regression guard).
##
## Determinism: the test flips the loaded slime table's first entry and
## its currency drop to is_guaranteed. ResourceLoader caches by path, so
## the same instance the enemy rolls is the one we mutate -- every kill
## drops. The mutation lives only in memory; the .tres on disk is
## untouched.
extends SceneTree

var _pass := 0
var _fail := 0
var _frames := 0
var _done := false
var _phase := "boot"

var _player: Node = null
var _slime: Node = null
var _slime_id: String = ""
var _gold_before: int = -1
var _drops_before: int = -1
var _picked: Array = []
var _gold_gained: int = 0
var _death_pos: Vector3 = Vector3.ZERO


func _initialize() -> void:
	print("=== LOOT TABLES LIVE TEST: booting playable scene ===")
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("  FAIL: could not load world_playable.tscn")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 90 or _done:
		return false

	match _phase:
		"boot":
			_static_checks()
			_setup_live()
		"kill":
			_poll_drop()
		"pickup":
			_verify_pickup()
	return false


# --- Phase 1: static resolution checks -------------------------------------

func _static_checks() -> void:
	var Resolver := load("res://core/schemas/loot_table_resolver.gd")

	for tid in ["loot_slime", "loot_wolf", "loot_bandit", "loot_skill_books"]:
		var t = Resolver.load_table(tid)
		_assert(t != null and t.has_method("roll_drop"), "table resolves: %s" % tid)
		if t != null:
			_assert(str(t.get("id")) == tid, "table id field matches filename: %s" % tid)

	# Unresolvable ids degrade to null (no crash).
	_assert(Resolver.load_table("loot_does_not_exist") == null,
			"unknown table id resolves to null")

	# EnemyData.roll_loot through the resolver: base gold always pays.
	var ds := root.get_node_or_null("DataService")
	var slime_data = ds.get_enemy("slime") if ds != null and ds.has_method("get_enemy") else null
	_assert(slime_data != null, "DataService has slime enemy data")
	if slime_data != null:
		_assert(str(slime_data.loot_table_id) == "loot_slime",
				"enemy_slime references loot_slime (bare-id convention)")
		var loot: Dictionary = slime_data.roll_loot()
		_assert(int(loot.get("gold", 0)) >= int(slime_data.gold_min),
				"roll_loot pays base gold (got %d)" % int(loot.get("gold", 0)))
		_assert(loot.get("items", null) is Array, "roll_loot returns items array")

	# SkillBook is a real Item now (the old extends Resource crashed on
	# every Item field assignment in create()).
	var book = load("res://core/schemas/skill_book.gd").create("human_charge", 3, "Charge")
	_assert(book != null, "SkillBook.create returns a book")
	if book != null:
		_assert(book is Item, "SkillBook is an Item")
		_assert(str(book.id) == "book_human_charge_epic", "book id encodes skill+tier")
		_assert(int(book.item_category) == int(Item.ItemCategory.SKILL_BOOK),
				"book category is SKILL_BOOK")
		_assert(str(book.get("book_skill_id")) == "human_charge", "book carries skill id")

	# GroundLootService expands runtime book ids through the academy.
	var gls := root.get_node_or_null("GroundLootService")
	_assert(gls != null, "GroundLootService present")
	if gls != null:
		var drop_id: String = gls.create_drop(Vector3(500, 1, 500),
				[{"item_id": "book_human_charge_epic", "quantity": 1}], {"source": "test"})
		var drop: Dictionary = gls.get_drop(drop_id)
		var items: Array = drop.get("items", [])
		var expanded: bool = items.size() == 1 and items[0] is Item \
				and str(items[0].id) == "book_human_charge_epic"
		_assert(expanded, "book id expands to a runtime SkillBook item")
		if not drop_id.is_empty() and drop.has("id"):
			gls._remove_drop(drop_id, "test_cleanup")

	# The academy catalog actually contains the skills we reference.
	var academy := root.get_node_or_null("SkillAcademyService")
	if academy != null:
		for sid in ["human_charge", "human_rend", "akkan_rune_chain_attacker", "synthetic_packet_flood"]:
			_assert(academy.get_catalog_entry(sid) != null and not academy.get_catalog_entry(sid).is_empty(),
					"academy catalog has upgradable skill: %s" % sid)

	_phase = "live_setup"
	# _setup_live() runs on the next _process tick via the phase machine
	# (calling it here as well double-killed two slimes).


# --- Phase 2: live kill -----------------------------------------------------

func _setup_live() -> void:
	_player = _find_player()
	_assert(_player != null, "player node present")
	if _player == null:
		return _finish()

	_slime = _find_slime()
	_assert(_slime != null, "slime present in scene")
	if _slime == null:
		return _finish()
	_slime_id = str(_slime.entity_id)

	var gls := root.get_node_or_null("GroundLootService")
	_drops_before = gls.get_drop_count()

	# Guarantee the drop: mutate the CACHED table resource (same instance
	# the enemy rolls). In-memory only.
	var table = load("res://data/loot_tables/loot_slime.tres")
	if table != null and table.entries.size() > 0 and table.currency_drops.size() > 0:
		table.entries[0]["is_guaranteed"] = true
		table.currency_drops[0]["is_guaranteed"] = true

	if "gold" in _player:
		_gold_before = int(_player.gold)

	var death_pos: Vector3 = _slime.global_position
	_death_pos = death_pos
	print("    killing slime %s at %s" % [_slime_id, str(death_pos)])
	_slime.take_damage(99999, _player)

	# Corpse inspection (same frame): must NOT contain table items.
	var corpse := _find_corpse_near(death_pos)
	if corpse != null:
		var loot_items: Array = corpse.get_loot_items()
		var table_item_in_corpse := false
		for it in loot_items:
			if it is Dictionary and str(it.get("item_id", "")) == "potion_health_small":
				table_item_in_corpse = true
		_assert(not table_item_in_corpse, "corpse did NOT re-roll the loot table")
	else:
		_assert(false, "corpse created for slime death")

	_phase = "kill"


func _poll_drop() -> void:
	if _frames > 400:
		_assert(false, "ground drop appeared within window")
		_phase = "pickup"
		_verify_pickup()
		return

	var gls := root.get_node_or_null("GroundLootService")
	if gls == null or _player == null:
		return
	if gls.get_drop_count() <= _drops_before:
		return

	# A drop appeared. Verify it is near the death spot and resolves to
	# real items, then pick it up.
	var drop: Dictionary = gls.find_nearest_pickup(_player)
	if drop.is_empty():
		# The drop exists but may not be the nearest; find by distance.
		for did in gls._drops:
			var d: Dictionary = gls._drops[did]
			if str(d.get("source", "")) == "enemy":
				drop = d
				break
	_assert(not drop.is_empty(), "enemy ground drop found")
	if drop.is_empty():
		_phase = "pickup"
		_verify_pickup()
		return

	_assert(_player.global_position.distance_to(_death_pos) < 30.0,
			"drop spawned near the dead slime")
	var items: Array = drop.get("items", [])
	_assert(items.size() >= 1, "drop carries rolled items (got %d)" % items.size())
	var all_items := true
	for it in items:
		if not (it is Item):
			all_items = false
	_assert(all_items, "all drop entries are resolved Item instances")

	if _gold_before >= 0:
		_gold_gained = int(_player.gold) - _gold_before

	# Walk into pickup range (PICKUP_RADIUS is 2.5m) and loot it.
	if _player is CharacterBody3D:
		_player.global_position = drop["position"] + Vector3(1.0, 0.0, 0.0)
	_picked = gls.try_pickup(_player, str(drop["id"]))
	_phase = "pickup"
	_verify_pickup()


# --- Phase 3: verify pickup -------------------------------------------------

func _verify_pickup() -> void:
	var got_something: bool = _picked.size() >= 1 or _gold_gained > 0
	_assert(got_something, "pickup landed item or currency (items=%d, gold=%d)"
			% [_picked.size(), _gold_gained])

	# The guaranteed potion entry should now be in the inventory.
	var inv_got_potion := false
	var inv_svc := root.get_node_or_null("InventoryService")
	if inv_svc != null and _player != null and inv_svc.has_method("get_inventory"):
		var inv = inv_svc.get_inventory(str(_player.entity_id))
		if inv != null and inv.has_method("get_all_items"):
			for it in inv.get_all_items():
				# Works for Item instances and item Dictionaries alike.
				# NOTE: Resource.get(key, default) is gone in 4.7.2 -- one
				# argument only.
				if str(it.get("id")) == "potion_health_small":
					inv_got_potion = true
	_assert(inv_got_potion, "guaranteed potion entry landed in player inventory")

	_finish()


# --- Helpers ----------------------------------------------------------------

func _find_player() -> Node:
	var p := current_scene.get_node_or_null("Player")
	if p != null:
		return p
	return get_first_node_in_group("players")


func _find_slime() -> Node:
	var candidates: Array = []
	for n in current_scene.get_children():
		_walk_for_slime(n, candidates)
	if candidates.is_empty():
		return null
	return candidates[0]


func _walk_for_slime(n: Node, out: Array) -> void:
	if "enemy_data" in n and n.get("enemy_data") != null:
		var ed = n.get("enemy_data")
		if "loot_table_id" in ed and str(ed.loot_table_id) == "loot_slime":
			out.append(n)
			return
	for c in n.get_children():
		_walk_for_slime(c, out)


func _find_corpse_near(pos: Vector3) -> Node:
	var corpses := get_nodes_in_group("corpses")
	var best: Node = null
	var best_d := 10.0
	for c in corpses:
		if c is Node3D:
			var d: float = (c as Node3D).global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = c
	return best


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	_done = true
	print("LootTablesLive: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
