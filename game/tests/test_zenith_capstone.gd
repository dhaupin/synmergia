## Receipt: the level-60 capstone (Zenithforged) tier.
##
## The gear ladder golden -> silver -> mythril -> starmetal -> sunforged ->
## skyforged topped out at required_level 58 while the level cap is 60, so the
## top rung was missing. This receipt pins the capstone the way the catalog
## receipt pins integrity:
##
##   A. COVERAGE: every WeaponType (1..10) has a L60 item; every armor slot
##      (head/chest/legs/feet/gloves/shoulders) has a L60 piece; every
##      AccessoryType (1..5) has a L60 piece.
##   B. THE LADDER: the capstone sits ABOVE the prior rung -- L60 buys never
##      undercut the L58 priciest, armor_value climbs, and every piece is
##      required_level == item_level == 60 (inside the item).
##   C. THE SOURCE: loot_zenith_reach is a real L60 table whose every entry
##      resolves through DataService, and the band-57 elite wires to it.
##
## Receipt-lore: script-mode -- autoloads resolved from root at runtime; the
## families are walked with DirAccess exactly like test_item_catalog.
extends SceneTree

var _checks: int = 0
var _fails: int = 0

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
	print("--- ZENITH CAPSTONE: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)

func _load_family(sub: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://data/" + sub)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres"):
			var res = load("res://data/%s/%s" % [sub, fn])
			if res != null:
				out.append(res)
		fn = dir.get_next()
	return out

func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)
	if ds == null:
		_finish()
		return

	var weapons: Array = _load_family("weapons")
	var armors: Array = _load_family("armors")
	var accessories: Array = _load_family("accessories")

	var z_weapons: Array = []
	var z_armors: Array = []
	var z_acc: Array = []
	for w in weapons:
		if str(w.id).begins_with("wep_zenithforged_"):
			z_weapons.append(w)
	for a in armors:
		if str(a.id).begins_with("arm_zenithforged_"):
			z_armors.append(a)
	for c in accessories:
		if str(c.id).begins_with("acc_") and str(c.id).ends_with("_zenithforged"):
			z_acc.append(c)

	# A. COVERAGE -- one weapon per WeaponType 1..10.
	var wt_seen: Dictionary = {}
	for w in z_weapons:
		wt_seen[int(w.weapon_type)] = true
	var wt_missing: Array = []
	for wt in range(1, 11):
		if not wt_seen.has(wt):
			wt_missing.append(wt)
	_check("every WeaponType (1..10) has a L60 capstone (%d weapons)" % z_weapons.size(),
		wt_missing.is_empty())
	if not wt_missing.is_empty():
		print("    missing weapon types: " + str(wt_missing))

	# A. COVERAGE -- every armor slot head(1)/chest(2)/legs(3)/feet(4)/gloves(5)/shoulders(6).
	var as_seen: Dictionary = {}
	for a in z_armors:
		as_seen[int(a.equip_slot)] = true
	var as_missing: Array = []
	for sl in range(1, 7):
		if not as_seen.has(sl):
			as_missing.append(sl)
	_check("every armor slot (head..shoulders) has a L60 capstone (%d pieces)" % z_armors.size(),
		as_missing.is_empty())
	if not as_missing.is_empty():
		print("    missing armor slots: " + str(as_missing))

	# A. COVERAGE -- every ArmorType 1..4 (cloth/leather/mail/plate). The
	# first pass authored plate only, so the 18 classes that cannot wear
	# plate had no capstone at all (can_use_armor is real). One piece per
	# material per slot is the law now.
	var at_seen_mat: Dictionary = {}
	for a in z_armors:
		at_seen_mat[int(a.armor_type)] = true
	var mat_missing: Array = []
	for at in range(1, 5):
		if not at_seen_mat.has(at):
			mat_missing.append(at)
	_check("every ArmorType (1..4) has a L60 capstone (%d armors)" % z_armors.size(),
		mat_missing.is_empty())
	if not mat_missing.is_empty():
		print("    missing armor types: " + str(mat_missing))

        # A. COVERAGE -- every AccessoryType 1..5 (ring/necklace/bracelet/cloak/belt).
	var at_seen: Dictionary = {}
	for c in z_acc:
		at_seen[int(c.accessory_type)] = true
	var at_missing: Array = []
	for at in range(1, 6):
		if not at_seen.has(at):
			at_missing.append(at)
	_check("every AccessoryType (1..5) has a L60 capstone (%d pieces)" % z_acc.size(),
		at_missing.is_empty())
	if not at_missing.is_empty():
		print("    missing accessory types: " + str(at_missing))

	# B. THE LADDER -- every capstone piece is required_level == item_level == 60.
	var req_bad: Array = []
	for res in z_weapons + z_armors + z_acc:
		if int(res.required_level) != 60 or int(res.item_level) != 60:
			req_bad.append("%s (%d/%d)" % [res.id, res.required_level, res.item_level])
	_check("every capstone piece is required_level == item_level == 60", req_bad.is_empty())
	if not req_bad.is_empty():
		print("    offenders: " + str(req_bad))

	# B. THE LADDER -- L60 buys never undercut the L58 priciest weapon/armor.
	var l58_max_w: int = 0
	for w in weapons:
		if int(w.required_level) == 58:
			l58_max_w = maxi(l58_max_w, int(w.buy_price))
	var z_min_w: int = 1 << 30
	for w in z_weapons:
		z_min_w = mini(z_min_w, int(w.buy_price))
	_check("L60 weapon buys sit above the L58 ceiling (%d > %d)" % [z_min_w, l58_max_w],
		z_min_w > l58_max_w)

	var l58_max_a: int = 0
	for a in armors:
		if int(a.required_level) == 58:
			l58_max_a = maxi(l58_max_a, int(a.buy_price))
	var z_min_a: int = 1 << 30
	for a in z_armors:
		z_min_a = mini(z_min_a, int(a.buy_price))
	_check("L60 armor buys sit above the L58 ceiling (%d > %d)" % [z_min_a, l58_max_a],
		z_min_a > l58_max_a)

	# B. THE LADDER -- the armor ceiling climbs past the L58 ceiling. Armor
	# value is per-slot (a helm carries less than a chest), so the law is
	# that the BEST L60 piece beats the BEST L58 piece, not the floor.
	var l58_max_av: int = 0
	for a in armors:
		if int(a.required_level) == 58:
			l58_max_av = maxi(l58_max_av, int(a.armor_value))
	var z_max_av: int = 0
	for a in z_armors:
		z_max_av = maxi(z_max_av, int(a.armor_value))
	_check("L60 armor ceiling climbs past the L58 ceiling (%d > %d)" % [z_max_av, l58_max_av],
		z_max_av > l58_max_av)

	# C. THE SOURCE -- loot_zenith_reach is real, L60, and every entry resolves.
	var table = load("res://data/loot_tables/loot_zenith_reach.tres")
	_check("loot_zenith_reach loads", table != null)
	if table != null:
		_check("loot_zenith_reach is level 60 (%d)" % int(table.level), int(table.level) == 60)
		var phantom: Array = []
		for e in table.entries:
			var iid: String = str(e.get("item_id", ""))
			if iid.is_empty() or ds.get_item(iid) == null:
				phantom.append(iid)
		_check("every loot_zenith_reach entry resolves through DataService (%d entries)" % table.entries.size(),
			phantom.is_empty())
		if not phantom.is_empty():
			print("    phantom items: " + str(phantom))

	# C. THE SOURCE -- the band-57 elite wires to the capstone table.
	var ledge = load("res://data/enemies/enemy_ledgewarden_construct.tres")
	_check("the band-57 elite wires loot_table_id = loot_zenith_reach",
		ledge != null and str(ledge.loot_table_id) == "loot_zenith_reach")

	_finish()
