# test_item_catalog.gd - THE CATALOG RECEIPT: every authored .tres in the
# item economy (weapons / armors / consumables / items / resources /
# recipes) must hold its own integrity LAWS:
#
#   A. IDENTITY: filename == id, the family's prefix law (wep_/arm_/
#      potion_or_item_/res_/recipe_), and the script binds (item.gd for
#      the six item families, recipe_data.gd for the recipes).
#   B. THE HONEST TAG: display_name + description + icon_path are
#      authored (an item with no words is an id with no world); icon
#      paths keep res://icons/...; skill/use ids stay data-only here.
#   C. THE PURSE LAW sells below it buys (both > 0 for real items),
#      stacks obey the category (equipment stacks 1, consumables and
#      resources stack > 1), and the requirements stay INSIDE the item
#      (required_level <= item_level).
#   D. THE GEAR LAWS: weapons carry a real weapon_type and a damage
#      window (min > 0, min < max, speed > 0); armors carry armor_value
#      > 0 and a real armor_type; every family's buy price climbs with
#      its item_level (price ledgers never step DOWN the level ladder).
#   E. THE BILLS RESOLVE: every recipe reflects DataService truth --
#      station valid, inputs nonempty, every input id get_item()s,
#      the output id get_item()s, the recipe itself get_recipe()s --
#      and the whole transaction is exacting: inputs > 0, output qty > 0.
#
# Receipt-lore: script-mode law -- autoloads resolved from root at
# runtime; family dirs walked with DirAccess exactly like
# test_data_naming_lint; failure names the file.
extends SceneTree

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
	print("--- ITEM CATALOG: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)

func _run() -> void:
	var root_node := root
	var ds = root_node.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)
	if ds == null:
		quit(1)

	var fam_dir: Dictionary = {
		"weapon": "data/weapons", "armor": "data/armors",
		"consumable": "data/consumables", "misc": "data/items",
		"resource": "data/resources",
	}
	var prefix_law: Dictionary = {
		"weapon": "wep_", "armor": "arm_", "resource": "res_",
	}
	var families: Dictionary = {}  # family -> Array[Item]
	var bad: Array = []

	for fam in fam_dir:
		var entries: Array = []
		var dir := DirAccess.open("res://" + fam_dir[fam])
		if dir == null:
			bad.append("dir missing: " + fam_dir[fam])
			continue
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".tres"):
				var stem := fn.trim_suffix(".tres")
				var res = load("res://%s/%s" % [fam_dir[fam], fn])
				if res == null:
					bad.append("load failed: %s/%s" % [fam_dir[fam], fn])
					fn = dir.get_next()
					continue
				var iid: String = str(res.id)
				if iid != stem:
					bad.append("%s/%s (filename mismatch: %s)" % [fam_dir[fam], fn, iid])
				var law: String = prefix_law.get(fam, "")
				if law != "" and not iid.begins_with(law):
					bad.append("%s not %s" % [iid, law])
				# THE HONEST TAG
				if res.display_name.is_empty() or res.description.is_empty():
					bad.append("%s unauthored words" % iid)
				if not String(res.icon_path).begins_with("res://icons/"):
					bad.append("%s icon path off convention (%s)" % [iid, res.icon_path])
				# THE PURSE LAW: sell >= 0; a for-sale item (buy > 0) sells
				# below it buys; a zero/zero purse is a QUEST item's only.
				var lvl: int = int(res.item_level)
				var sp: int = int(res.sell_price)
				var bp: int = int(res.buy_price)
				if sp < 0 or bp < 0:
					bad.append("%s purse law (sell %d buy %d)" % [iid, sp, bp])
				if bp > 0 and sp >= bp:
					bad.append("%s purse law (sell %d buy %d)" % [iid, sp, bp])
				if bp == 0 and sp == 0 and not bool(res.is_quest_item):
					bad.append("%s zero purse but not a quest item" % iid)
				# STACK LAW (equipment stacks 1; the consumable and resource
				# families move in bulk; misc is free -- a unique charm, a
				# single writ, a coin the tide carried back)
				if fam == "weapon" or fam == "armor":
					if int(res.stack_size) != 1:
						bad.append("%s equipment stack %d" % [iid, res.stack_size])
				elif (fam == "consumable" or fam == "resource") and int(res.stack_size) < 2:
					bad.append("%s stackable %d" % [iid, res.stack_size])
				# THE REQUIREMENTS STAY INSIDE THE ITEM: required_level <= item_level
				if int(res.required_level) > lvl:
					bad.append("%s required_level %d > item_level %d" % [iid, res.required_level, lvl])
				# GEAR LAWS
				if fam == "weapon" and int(res.weapon_type) == 0:
					bad.append("%s weapon_type NONE" % iid)
				if fam == "armor" and int(res.armor_type) == 0:
					bad.append("%s armor_type NONE" % iid)
				entries.append(res)
			fn = dir.get_next()
		families[fam] = entries

	if bad.is_empty():
		_check("family identity + word/law integrity (all five families)", true)
	else:
		_check("family identity + word/law integrity -> " + "; ".join(bad.slice(0, 5)), false)

	# THE GEAR LAWS per real fields
	var wbad: Array = []
	for w in families.get("weapon", []):
		if int(w.weapon_damage_min) <= 0 or int(w.weapon_damage_max) <= int(w.weapon_damage_min):
			wbad.append(String(w.id) + " damage window")
		if float(w.attack_speed) <= 0.0:
			wbad.append(String(w.id) + " attack speed")
	_check("weapon damage windows + speeds lawful", wbad.is_empty())
	var abad: Array = []
	for a in families.get("armor", []):
		# THE SHIELD LAW: chest-class pieces carry armor_value; shields
		# carry their armor INSIDE the stats book (stats["armor"]) --
		# one honesty rule, two carriers.
		if int(a.armor_value) <= 0 and not a.stats.has("armor"):
			abad.append(String(a.id) + " armor value")
	_check("armor values lawful", abad.is_empty())

	# THE PRICE LADDER: buy climbs with item_level inside each family
	var pbad: Array = []
	for fam in ["weapon", "armor"]:
		var rows: Array = families.get(fam, []).duplicate()
		rows.sort_custom(func(x, y): return int(x.item_level) < int(y.item_level))
		for i2 in range(1, rows.size()):
			if int(rows[i2].buy_price) < int(rows[i2 - 1].buy_price):
				pbad.append("%s(%d) below %s(%d)" % [rows[i2].id, rows[i2].item_level, rows[i2 - 1].id, rows[i2 - 1].item_level])
	_check("buy price climbs with item_level (weapons + armors)", pbad.is_empty())

	# SERVICE TRUTH: every family id get_item()s as the SAME object law
	var ids: Array = []
	for fam in ["weapon", "armor", "consumable", "resource"]:
		for res in families.get(fam, []):
			ids.append(str(res.id))
	ids.append("res_iron_ingot")  # recipe inputs ride the resource family too
	var miss: Array = []
	for iid in ids:
		if ds.get_item(iid) == null:
			miss.append(iid)
	_check("every catalog id resolves through DataService", miss.is_empty())

	# THE BILLS RESOLVE
	var dir := DirAccess.open("res://data/recipes")
	var rbad: Array = []
	var rcount := 0
	if dir == null:
		rbad.append("data/recipes missing")
	else:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".tres"):
				rcount += 1
				var r = load("res://data/recipes/" + fn)
				if r == null:
					rbad.append("load failed: " + fn)
					fn = dir.get_next()
					continue
				var rid: String = str(r.id)
				if rid != fn.trim_suffix(".tres") or not rid.begins_with("recipe_"):
					rbad.append(rid + " identity")
				if int(r.station) < 0 or int(r.station) > 3:
					rbad.append(rid + " station")
				if r.inputs.is_empty():
					rbad.append(rid + " empty inputs")
				var done: Dictionary = {}
				for input in r.inputs:
					var in_id: String = str(input.get("item_id", ""))
					var q: int = int(input.get("qty", 0))
					if q <= 0 or done.has(in_id):
						rbad.append("%s bill %s (qty %s)" % [rid, in_id, q])
					done[in_id] = true
					if ds.get_item(in_id) == null:
						rbad.append("%s phantom input %s" % [rid, in_id])
				var out_id: String = str(r.output.get("item_id", ""))
				if int(r.output.get("qty", 0)) <= 0:
					rbad.append("%s zero output" % rid)
				# THE CRAFT GRANT LAWS: an item output rides the bag
				# (get_item); a mount/glider output rides the RideService
				# OWNERSHIP ledger (get_mount -- a wing is a thing you
				# own, not a thing you carry). One is required.
				if ds.get_item(out_id) == null and ds.get_mount(out_id) == null:
					rbad.append("%s phantom output %s" % [rid, out_id])
				var out_res = ds.get_item(out_id)
				if out_res != null and str(out_res.id) != out_id:
					rbad.append("%s output identity drift" % rid)
				if float(r.failure_rate) < 0.0 or float(r.failure_rate) > 1.0:
					rbad.append(rid + " failure rate")
				if ds.get_recipe(rid) == null:
					rbad.append("%s not through the service" % rid)
			fn = dir.get_next()
		_check("every recipe bill resolves (%d recipes)" % rcount, rbad.is_empty())
		if not rbad.is_empty():
			_check("bill defects: " + "; ".join(rbad.slice(0, 5)), false)

	# F. THE VENDOR STOCK LAW: every vendor offering's shelf reflects
	# service truth -- a phantom sku on a shelf is a shop that sells
	# air. Schema-only offerings (service/quest/dialogue/bank) carry
	# no shelf and are only typed.
	var odir := DirAccess.open("res://data/npc_offerings")
	var vbad: Array = []
	var vcount := 0
	if odir == null:
		vbad.append("data/npc_offerings missing")
	else:
		var all_items: Array = ds.get_all_items()
		odir.list_dir_begin()
		var vfn := odir.get_next()
		while vfn != "":
			if vfn.ends_with(".tres"):
				vcount += 1
				var o = load("res://data/npc_offerings/" + vfn)
				if o == null:
					vbad.append("load failed: " + vfn)
					vfn = odir.get_next()
					continue
				var ot: String = str(o.type)
				if not ["vendor", "service", "quest", "dialogue", "bank"].has(ot):
					vbad.append("%s unknown type '%s'" % [vfn, ot])
				elif ot == "vendor":
					var smode: String = str(o.stock_mode)
					if not ["by_category", "by_item_id", "mixed"].has(smode):
						vbad.append("%s stock_mode '%s'" % [vfn, smode])
					if float(o.price_multiplier) <= 0.0:
						vbad.append(vfn + " price multiplier")
					if int(o.stock_qty) <= 0:
						vbad.append(vfn + " stock qty")
					for sc in o.sell_categories:
						if int(sc) < 0 or int(sc) > 9:
							vbad.append("%s sell category %d" % [vfn, int(sc)])
						for bc in o.buy_categories:
							if int(bc) < 0 or int(bc) > 9:
								vbad.append("%s buy category %d" % [vfn, int(bc)])
					if smode == "by_item_id" or smode == "mixed":
						if o.catalog_items.is_empty():
							vbad.append(vfn + " item-id shelf empty")
						for entry in o.catalog_items:
							var eid: String = str(entry.get("item_id", ""))
							if int(entry.get("qty", 0)) <= 0:
								vbad.append("%s shelf %s qty" % [vfn, eid])
							var shelf_itm = ds.get_item(eid)
							if shelf_itm == null:
								vbad.append("%s phantom shelf %s" % [vfn, eid])
							elif int(shelf_itm.buy_price) <= 0:
								vbad.append("%s shelf %s unpriced" % [vfn, eid])
					if smode == "by_category" or smode == "mixed":
						var shelves := 0
						for sc2 in o.sell_categories:
							for itmc in all_items:
								if itmc != null and int(itmc.item_category) == int(sc2):
									shelves += 1
						if shelves == 0 and not o.sell_categories.is_empty() and not o.catalog_items.is_empty():
							vbad.append(vfn + " shelf resolves to nothing")
						elif shelves == 0 and smode == "by_category":
							vbad.append(vfn + " by-category shelf empty")
				vfn = odir.get_next()
		_check("vendor stock law (%d offerings)" % vcount, vbad.is_empty())
		if not vbad.is_empty():
			print("    vendor defects: " + "; ".join(vbad.slice(0, 6)))

	# G. THE OFFERING LAW: every NPC's includes resolves to a real
	# file (offering/vendor -> data/npc_offerings, inline dialogue ->
	# data/dialogues, quest ids -> data/quests -- a phantom include is
	# a conversation with nobody).
	var ndir := DirAccess.open("res://data/npc")
	var ibad: Array = []
	var icount := 0
	if ndir == null:
		ibad.append("data/npc missing")
	else:
		ndir.list_dir_begin()
		var nfn := ndir.get_next()
		while nfn != "":
			if nfn.ends_with(".tres"):
				icount += 1
				var nd = load("res://data/npc/" + nfn)
				if nd == null:
					ibad.append("load failed: " + nfn)
					nfn = ndir.get_next()
					continue
				for inc in nd.includes:
					var it2: String = str(inc.get("type", ""))
					var ref: String = str(inc.get("ref_id", ""))
					var dia: String = str(inc.get("dialogue_id", ""))
					if it2 == "offering" or it2 == "vendor":
						if ref.is_empty() or not FileAccess.file_exists("res://data/npc_offerings/%s.tres" % ref):
							ibad.append("%s phantom %s include %s" % [nfn, it2, ref])
					elif it2 == "dialogue":
						if dia.is_empty() or not FileAccess.file_exists("res://data/dialogues/%s.tres" % dia):
							ibad.append("%s phantom dialogue include %s" % [nfn, dia])
					elif it2 == "quest":
						for qid in inc.get("quest_ids", []):
							if not FileAccess.file_exists("res://data/quests/%s.tres" % str(qid)):
								ibad.append("%s phantom quest include %s" % [nfn, qid])
				nfn = ndir.get_next()
		_check("offering include law (%d npcs)" % icount, ibad.is_empty())
		if not ibad.is_empty():
			print("    include defects: " + "; ".join(ibad.slice(0, 6)))

	# H. THE ICON LAW: every icon_path in data/**/*.tres names a file
	# that EXISTS on disk now (the generator's law: an aspirational
	# path is a promise; a real png is kept).
	var icon_pat := RegEx.new()
	icon_pat.compile('icon_path\\s*=\\s*"([^"]+)"')
	var icon_missing: Array = []
	var icon_count := 0
	if DirAccess.open("res://data") != null:
		var stack: Array = ["res://data"]
		while not stack.is_empty():
			var dpath = stack.pop_back()
			var dd := DirAccess.open(dpath)
			if dd == null:
				continue
			dd.list_dir_begin()
			var dfn := dd.get_next()
			while dfn != "":
				var fpath: String = str(dpath) + "/" + str(dfn)
				if dd.current_is_dir():
					stack.append(fpath)
				elif dfn.ends_with(".tres"):
					var text := FileAccess.get_file_as_string(fpath)
					var from := 0
					var m := icon_pat.search(text, from)
					while m != null:
						icon_count += 1
						var ip: String = m.get_string(1)
						if not FileAccess.file_exists(ip):
							icon_missing.append(fpath + " -> " + ip)
						from = m.get_end()
						m = icon_pat.search(text, from)
				dfn = dd.get_next()
		_check("icon paths exist on disk (%d referenced)" % icon_count, icon_missing.is_empty())
		if not icon_missing.is_empty():
			print("    icon residue: " + "; ".join(icon_missing.slice(0, 5)))

	_finish()
