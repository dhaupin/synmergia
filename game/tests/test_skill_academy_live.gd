## test_skill_academy_live.gd - LIVE skill academy verification.
## Run headless or rendering:
##
##   cd game && godot --headless --path . --script res://tests/test_skill_academy_live.gd
##
## Chains exercised (real autoloads, real inventory, real CharacterData):
##   1. Catalog: upgradable skills listed, signature skills excluded.
##   2. SkillBook.create -> a real Item (id book_<skill>_<tier>).
##   3. purchase_book: gold check, cost, book usable in inventory.
##   4. apply_upgrade FAIL with fewer than 4 matching-tier books.
##   5. apply_upgrade OK: 4 books CONSUMED FROM THE REAL INVENTORY
##      (regression guard for the infinite-book exploit where books were
##      only removed from the UI's local snapshot), skill point spent,
##      skill_upgrades advanced.
##   6. Reopen path (load_player_context source): books re-read from
##      InventoryService must NOT resurrect consumed books.
##   7. Tier matching: level 2 upgrade requires RARE books (level-1
##      common books do not count).
extends SceneTree

var _pass := 0
var _fail := 0
var _frames := 0
var _done := false


func _initialize() -> void:
	print("=== SKILL ACADEMY LIVE TEST ===")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30 and not _done:
		_run()
	return false


func _run() -> void:
	_done = true

	# --- 1. Catalog -----------------------------------------------------
	var svc = root.get_node_or_null("SkillAcademyService")
	_assert(svc != null, "SkillAcademyService present")
	if svc == null:
		return _finish()

	var entry = svc.get_catalog_entry("human_charge")
	_assert(entry != null and not entry.is_empty(), "catalog has upgradable human_charge")
	var sig = svc.get_catalog_entry("akkan_gravity_well")
	_assert(sig == null or sig.is_empty(), "signature skill excluded from catalog")

	# --- 2. SkillBook is a real Item ------------------------------------
	var book = svc.create_book("human_charge", "common")
	_assert(book != null and book is Item, "create_book returns an Item")
	if book != null:
		_assert(str(book.id) == "book_human_charge_common", "book id encodes skill+tier")
		_assert(int(book.book_upgrade_level) == 1, "book carries upgrade level")

	# --- Player + inventory context -------------------------------------
	# Synthetic player id: the academy flow is service-level and only
	# needs a registered inventory + CharacterData, no scene node.
	var pid := "academy_test_player"

	var inv_svc = root.get_node_or_null("InventoryService")
	_assert(inv_svc != null, "InventoryService present")
	if inv_svc == null:
		return _finish()

	var inv = inv_svc.get_inventory(pid)
	if inv == null:
		inv = load("res://core/components/inventory_component.gd").new()
		inv_svc.register_inventory(pid, inv)
	_assert(inv != null, "inventory registered for %s" % pid)
	if inv == null:
		return _finish()

	# --- 3. Purchase ------------------------------------------------------
	var gold_before := int(inv.get_gold())
	if gold_before < 500:
		inv.add_gold(500 - gold_before)
	var purchase: Dictionary = svc.purchase_book(pid, "human_charge", int(inv.get_gold()))
	_assert(purchase.get("success", false), "purchase_book succeeds with gold")
	_assert(int(purchase.get("cost", 0)) == 100, "common book costs 100 gold")
	var bought: Item = purchase.get("book")
	_assert(bought != null, "purchase returns a book")
	if bought != null:
		_assert(inv.add_item(bought), "purchased book enters inventory")

	# Insufficient gold path.
	var broke: Dictionary = svc.purchase_book(pid, "human_charge", 10)
	_assert(not broke.get("success", true), "purchase_book rejects insufficient gold")

	# --- 4. Upgrade fails with too few books ------------------------------
	# CharacterData arrives via the SkillAcademyService's compile-time
	# global (character_data.gd itself carries bare autoload refs and is
	# not load()-safe in script mode).
	var char_data: CharacterData = CharacterData.new()
	# The stat gate is LIVE: a tier with no authored `min_stat` gates on the
	# character's focal stat (human_warrior -> strength). Fund it so the legs
	# below exercise the book economy rather than the gate.
	char_data.allocated_stats["strength"] = 120

	var one_book: Dictionary = svc.apply_upgrade(pid, "human_charge", char_data, [bought])
	_assert(not one_book.get("success", true), "upgrade fails with 1 of 4 books")
	_assert(str(one_book.get("reason", "")).begins_with("Need 4"),
			"failure reason names the book count (%s)" % str(one_book.get("reason", "")))

	# --- 5. Upgrade succeeds and burns real books --------------------------
	for i in range(3):
		var b: Item = svc.create_book("human_charge", "common")
		inv.add_item(b)

	var spent_before := int(char_data.spent_skill_points)
	var result: Dictionary = svc.apply_upgrade(pid, "human_charge", char_data,
			_inv_books(inv))
	_assert(result.get("success", false), "upgrade succeeds with 4 matching books")
	_assert(int(result.get("new_level", 0)) == 1, "skill upgraded to level 1")
	_assert(int(char_data.get_skill_upgrade_level("human_charge")) == 1,
			"skill_upgrades recorded level 1")
	_assert(int(char_data.spent_skill_points) == spent_before + 1,
			"one skill point spent")

	# THE EXPLOIT GUARD: the real store must no longer contain the books.
	var remaining := _count_books(inv, "book_human_charge_common")
	_assert(remaining == 0,
			"consumed books removed from REAL inventory (found %d)" % remaining)

	# --- 6. Reopen path does not resurrect ---------------------------------
	# Same read the UI's load_player_context performs after the fix.
	var reread := 0
	if inv_svc.get_inventory(pid) != null:
		reread = _count_books(inv_svc.get_inventory(pid), "book_human_charge_common")
	_assert(reread == 0, "reopen (load_player_context path) sees 0 books, no resurrection")

	# --- 7. Tier matching: level 2 wants RARE books -------------------------
	# 4 leftover COMMON books must NOT upgrade level 2.
	for i in range(4):
		var c: Item = svc.create_book("human_charge", "common")
		inv.add_item(c)
	var wrong_tier: Dictionary = svc.apply_upgrade(pid, "human_charge", char_data,
			_inv_books(inv))
	_assert(not wrong_tier.get("success", true),
			"level 2 upgrade rejects common-tier books (%s)" % str(wrong_tier.get("reason", "")))

	for i in range(4):
		var r: Item = svc.create_book("human_charge", "rare")
		inv.add_item(r)

	# THE STAT GATE: a fresh level-1 warrior (strength 14) cannot reach a rare
	# tier (needs 30) even holding all four books.
	var low_stat: CharacterData = CharacterData.new()
	low_stat.skill_upgrades = {"human_charge": 1}  # already at common; next is rare
	low_stat.spent_skill_points = 1
	var gated: Dictionary = svc.apply_upgrade(pid, "human_charge", low_stat, _inv_books(inv))
	_assert(not gated.get("success", true),
			"stat gate blocks a rare upgrade below the focal threshold")
	_assert(str(gated.get("reason", "")).begins_with("Requires"),
			"stat gate reason names the stat (%s)" % str(gated.get("reason", "")))

	var two: Dictionary = svc.apply_upgrade(pid, "human_charge", char_data,
			_inv_books(inv))
	_assert(two.get("success", false), "level 2 upgrade succeeds with 4 rare books")
	_assert(int(char_data.get_skill_upgrade_level("human_charge")) == 2,
			"skill_upgrades recorded level 2")
	_assert(_count_books(inv, "book_human_charge_rare") == 0,
			"rare books burned from real inventory")

	if inv_svc.has_method("persist_inventory"):
		inv_svc.persist_inventory(pid)

	_finish()


# --- Helpers ----------------------------------------------------------------

func _inv_books(inv) -> Array:
	var books: Array = []
	for item in inv.get_all_items():
		if item is SkillBook:
			books.append(item)
	return books


func _count_books(inv, book_id: String) -> int:
	var n := 0
	for item in inv.get_all_items():
		if item is SkillBook and str(item.id) == book_id:
			n += 1
	return n


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("SkillAcademyLive: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
