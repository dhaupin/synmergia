## Receipt: content ref integrity -- loot-table AND npc-offering item/currency ids resolve.
##
## Guards the exact silent-break class the data layer cannot: a loot entry whose
## item_id names no item (a typo, or a removed item) drops nothing at runtime
## with no error; a currency_id that names no currency is dropped by the
## consumers. Book entries are the one exception -- book_<skill>_<tier> ids are
## runtime-expanded by GroundLootService, so they validate as skill+tier AND
## the skill must be upgradable (the runtime catalog gate; a signature would
## silently drop nothing).
##
## The npc-offering half guards catalog_items: a vendor entry whose item_id or
## currency_id names nothing is a shop row that can never be bought. The enemy
## half guards loot_table_id / secondary_loot_table_id: a typo'd table id makes
## an enemy silently drop nothing.
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
						# The runtime gate is SkillAcademyService's catalog, which
						# holds UPGRADABLE skills only: create_book returns null
						# for a non-upgradable skill (a signature), so
						# GroundLootService skips the drop with only a warn --
						# the same silent-break class as a phantom item id.
						var sk = ds.get_skill(skill_id) if ds.has_method("get_skill") else null
						var upgradable: bool = sk != null and bool(sk.get("upgradable"))
						if not TIERS.has(tier) or not upgradable:
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

	var off_bad_items: Array = []
	var off_bad_curr: Array = []
	var odir := DirAccess.open("res://data/npc_offerings")
	if odir != null:
		odir.list_dir_begin()
		var of := odir.get_next()
		while of != "":
			if of.ends_with(".tres"):
				var o = load("res://data/npc_offerings/" + of)
				if o != null and "catalog_items" in o:
					for it in o.catalog_items:
						var oiid: String = str(it.get("item_id", ""))
						if not oiid.is_empty() and ds.get_item(oiid) == null:
							off_bad_items.append("%s: %s" % [of, oiid])
						var ocid: String = str(it.get("currency_id", ""))
						if not ocid.is_empty() and ocid != "gold" and ocid != "currency_gold" and ds.get_currency(ocid) == null:
							off_bad_curr.append("%s: %s" % [of, ocid])
				of = odir.get_next()
	_check("every offering catalog_items item_id resolves", off_bad_items.is_empty())
	if not off_bad_items.is_empty():
		print("    phantom offering items: " + str(off_bad_items))
	_check("every offering catalog_items currency_id resolves", off_bad_curr.is_empty())
	if not off_bad_curr.is_empty():
		print("    phantom offering currencies: " + str(off_bad_curr))

	var e_bad: Array = []
	var edir := DirAccess.open("res://data/enemies")
	if edir != null:
		edir.list_dir_begin()
		var ef := edir.get_next()
		while ef != "":
			if ef.ends_with(".tres"):
				var e = load("res://data/enemies/" + ef)
				if e != null:
					for key in ["loot_table_id", "secondary_loot_table_id"]:
						var tid: String = str(e.get(key))
						if not tid.is_empty():
							# The resolver tolerates a bare id or a full res:// path.
							var tpath: String = tid if tid.begins_with("res://") else "res://data/loot_tables/" + tid + ".tres"
							if not FileAccess.file_exists(tpath):
								e_bad.append("%s: %s=%s" % [ef, key, tid])
				ef = edir.get_next()
	_check("every enemy loot_table_id resolves", e_bad.is_empty())
	if not e_bad.is_empty():
		print("    phantom enemy loot refs: " + str(e_bad))

	# Spawn tables (the zone spawn rung): every entry's template_id must
	# resolve to a real enemy, and every zone_id must name a real zone.
	# A phantom here is a spawn point that silently places nothing.
	var st_bad_enemy: Array = []
	var st_bad_zone: Array = []
	var st_count: int = 0
	var sdir := DirAccess.open("res://data/spawn_tables")
	if sdir != null:
		sdir.list_dir_begin()
		var sf := sdir.get_next()
		while sf != "":
			if sf.ends_with(".tres"):
				st_count += 1
				var st = load("res://data/spawn_tables/" + sf)
				if st == null:
					st_bad_enemy.append(sf + " (load failed)")
				else:
					var zid: String = str(st.get("zone_id"))
					if not zid.is_empty() and ds.get_zone(zid) == null:
						st_bad_zone.append("%s -> %s" % [sf, zid])
					for e in st.get("entries"):
						if not (e is Dictionary):
							continue
						var etid: String = str(e.get("template_id", ""))
						if etid.is_empty():
							st_bad_enemy.append("%s: entry with empty template_id" % sf)
						elif ds.get_enemy(etid) == null:
							st_bad_enemy.append("%s: %s" % [sf, etid])
				sf = sdir.get_next()
	_check("every spawn-table entry template_id resolves (%d tables)" % st_count, st_bad_enemy.is_empty())
	if not st_bad_enemy.is_empty():
		print("    phantom spawn enemies: " + str(st_bad_enemy))
	_check("every spawn-table zone_id resolves", st_bad_zone.is_empty())
	if not st_bad_zone.is_empty():
		print("    phantom spawn zones: " + str(st_bad_zone))

	print("--- CONTENT REF INTEGRITY: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)
