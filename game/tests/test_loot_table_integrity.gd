## Receipt: loot-table integrity -- every entry item id and currency id resolves.
##
## Guards the exact silent-break class the data layer cannot: a loot entry whose
## item_id names no item (a typo, or a removed item) drops nothing at runtime
## with no error; a currency_id that names no currency is dropped by the
## consumers. Book entries are the one exception -- book_<skill>_<tier> ids are
## runtime-expanded by GroundLootService, so they validate as skill+tier.
extends SceneTree

const TIERS: Array = ["common", "rare", "epic", "legendary", "mythic"]

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

func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)
	if ds == null:
		quit(1)
		return

	var bad_items: Array = []
	var bad_books: Array = []
	var bad_curr: Array = []
	var tables: int = 0
	var dir := DirAccess.open("res://data/loot_tables")
	if dir == null:
		_check("data/loot_tables exists", false)
		quit(1)
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres"):
			tables += 1
			var t = load("res://data/loot_tables/" + fn)
			if t == null:
				bad_items.append(fn + " (load failed)")
			else:
				for e in t.entries:
					var iid: String = str(e.get("item_id", ""))
					if iid.is_empty():
						if e.has("currency_id"):
							bad_items.append("%s: currency row (currency_id=%s) misplaced in entries; move it to currency_drops" % [fn, str(e.get("currency_id", ""))])
						else:
							bad_items.append("%s: entry with empty item_id" % fn)
						continue
					if iid.begins_with("book_"):
						# book_<skill_id>_<tier> -- tier is the trailing token.
						var parts := iid.split("_")
						var tier: String = parts[parts.size() - 1] if parts.size() > 0 else ""
						var skill_id: String = iid.trim_prefix("book_").trim_suffix("_" + tier)
						if not TIERS.has(tier) or ds.get_skill(skill_id) == null:
							bad_books.append("%s: %s" % [fn, iid])
					elif ds.get_item(iid) == null:
						bad_items.append("%s: %s" % [fn, iid])
				for cd in t.currency_drops:
					var cid: String = str(cd.get("currency_id", "gold"))
					if cid == "gold" or cid == "currency_gold":
						continue
					if ds.get_currency(cid) == null:
						bad_curr.append("%s: %s" % [fn, cid])
		fn = dir.get_next()

	_check("every loot-table entry item id resolves through DataService (%d tables)" % tables, bad_items.is_empty())
	if not bad_items.is_empty():
		print("    phantom items: " + str(bad_items))
	_check("every runtime book_ entry names a real skill + tier", bad_books.is_empty())
	if not bad_books.is_empty():
		print("    bad books: " + str(bad_books))
	_check("every loot currency id resolves", bad_curr.is_empty())
	if not bad_curr.is_empty():
		print("    phantom currencies: " + str(bad_curr))

	print("--- LOOT TABLE INTEGRITY: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)
