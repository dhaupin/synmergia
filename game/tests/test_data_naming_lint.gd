extends SceneTree

## Data naming + reference lint.
##
## Freezes the id conventions decided 2026-09-25:
##   - NPC ids:        "npc_" prefix, filename == id (npc_village_elder.tres)
##   - Quest ids:      "quest_" prefix, filename == id
##   - Zone ids:       "zone_" prefix, filename == id
##   - Faction ids:    "faction_" prefix, filename == id
##   - Enemy ids:      bare ("wolf"); files keep the enemy_ prefix
##   - Item ids:       kind prefix (wep_, arm_, potion_, res_, misc_)
##   - Titles/achievements/etc: bare id, uniformly per category
##   - Offering refs:  bare filename key (NPCOffering has no id field)
##
## Also validates cross-file references so phantom ids (npc_alchemist,
## zone_village, npc_guard_captain -- all real historical bugs) can
## never come back:
##   - NPCData.zone_id must name an existing zone id
##   - quest giver/turn_in npc ids must exist
##   - quest next_quest_id / required_quests must exist
##   - offering quest_ids must exist
##   - dialogue npc_id must exist
##   - zone roster npc ids must exist
##   - Achievement title_reward must exist
##   - Acts: act_ prefix, filename == id, chapters present
##
## Run: godot --headless --path . --script res://tests/test_data_naming_lint.gd

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- DATA NAMING LINT: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

## Scan a data dir, return {filename_base: id} for every .tres that has
## an `id = "..."` line (data files without a top-level id are skipped).
func _load_ids(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://" + dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var txt := FileAccess.get_file_as_string("res://%s/%s" % [dir_path, f])
			for line in txt.split("\n"):
				var t := line.strip_edges()
				if t.begins_with("id = \""):
					out[f.trim_suffix(".tres")] = t.trim_prefix("id = \"").trim_suffix("\"")
					break
		f = dir.get_next()
	return out

func _has_prefix(ids: Dictionary, prefix: String, label: String) -> void:
	var bad: Array = []
	for base in ids:
		if not str(ids[base]).begins_with(prefix):
			bad.append(str(ids[base]))
		if base != str(ids[base]):
			bad.append("%s (filename mismatch: %s.tres)" % [str(ids[base]), base])
	if bad.is_empty():
		_ok("%s: all %d ids use '%s' prefix, filename == id" % [label, ids.size(), prefix])
	else:
		_fail("%s style violations: %s" % [label, ", ".join(bad)])

func _file_text(dir_path: String, base: String) -> String:
	return FileAccess.get_file_as_string("res://%s/%s.tres" % [dir_path, base])


## Every quest id named in a text blob by any `"quest_ids": [...]` key
## (inline NPC includes and offering files share this shape; entries may
## sit on one line or wrap). Regex over the whole text, not line-based,
## so a single-line include dict is parsed too.
func _quest_ids_in(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("quest_ids\\\"?\\s*[:=]\\s*\\[([^\\]]*)\\]")
	for m in re.search_all(text):
		for part in m.get_string(1).split(","):
			var v := part.strip_edges().trim_prefix("\"").trim_suffix("\"")
			if v != "":
				out.append(v)
	return out

func _load_display_names(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://" + dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var txt := FileAccess.get_file_as_string("res://%s/%s" % [dir_path, f])
			for line in txt.split("\n"):
				var t := line.strip_edges()
				if t.begins_with("display_name = \""):
					out[t.trim_prefix("display_name = \"").trim_suffix("\"")] = true
					break
		f = dir.get_next()
	return out

## Matches an authored objective dict's type + target, e.g.
##   {"id": "...", "type": 13, "target": "glide_distance", "count": 1}
func _objective_regex() -> RegEx:
	var re := RegEx.new()
	re.compile("\"type\":\\s*(\\d+),\\s*\"target\":\\s*\"([^\"]*)\"")
	return re

## Matches a quoted skill id inside a class ref list (e.g. "akkan_rune_strike").
func _skill_ref_regex() -> RegEx:
	var re := RegEx.new()
	re.compile("\"([a-z0-9_]+)\"")
	return re

## Return the text between the opening bracket after `key =` and its match.
## Handles single-line and multi-line arrays/dicts; "" when the key is absent.
func _bracket_block(txt: String, key: String) -> String:
	var m := RegEx.new()
	m.compile("(^|\\n)\\s*" + key + "\\s*=\\s*([\\[{])")
	var mm := m.search(txt)
	if mm == null:
		return ""
	var open_idx := mm.get_end() - 1
	var open := txt[open_idx]
	var close := "]" if open == "[" else "}"
	var depth := 0
	for i in range(open_idx, txt.length()):
		var c := txt[i]
		if c == open:
			depth += 1
		elif c == close:
			depth -= 1
			if depth == 0:
				return txt.substr(open_idx, i - open_idx + 1)
	return txt.substr(open_idx)

func _run() -> void:
	var npc_ids := _load_ids("data/npc")
	var quest_ids := _load_ids("data/quests")
	var zone_ids := _load_ids("data/zones")
	var faction_ids := _load_ids("data/factions")
	var enemy_ids := _load_ids("data/enemies")
	var dialogue_ids := _load_ids("data/dialogues")

	# --- Style: prefixed categories, filename == id ---
	_has_prefix(npc_ids, "npc_", "NPCs")
	_has_prefix(quest_ids, "quest_", "Quests")
	_has_prefix(zone_ids, "zone_", "Zones")
	_has_prefix(faction_ids, "faction_", "Factions")
	_has_prefix(_load_ids("data/gates"), "gate_", "Ward gates")
	_has_prefix(_load_ids("data/spawn_tables"), "spawn_", "Spawn tables")

	# --- Style: enemy ids stay bare (files carry the enemy_ prefix) ---
	var bad_enemies: Array = []
	for base in enemy_ids:
		if str(enemy_ids[base]).begins_with("enemy_"):
			bad_enemies.append(str(enemy_ids[base]))
		if not base.begins_with("enemy_"):
			bad_enemies.append("%s.tres (file prefix mismatch)" % base)
	if bad_enemies.is_empty():
		_ok("Enemies: bare ids, enemy_ file prefix, %d files" % enemy_ids.size())
	else:
		_fail("Enemy style violations: %s" % ", ".join(bad_enemies))

	# --- NPC zone_id references resolve ---
	var zone_id_set := {}
	for base in zone_ids:
		zone_id_set[zone_ids[base]] = true
	var bad_zones: Array = []
	for base in npc_ids:
		var txt := _file_text("data/npc", base)
		for line in txt.split("\n"):
			if line.begins_with("zone_id = \"") and not line.begins_with("zone_id = \"\""):
				var zid := line.strip_edges().trim_prefix("zone_id = \"").trim_suffix("\"")
				if not zone_id_set.has(zid):
					bad_zones.append("%s -> %s" % [str(npc_ids[base]), zid])
	if bad_zones.is_empty():
		_ok("NPC zone_id refs all resolve")
	else:
		_fail("Phantom zone refs: %s" % ", ".join(bad_zones))

	# --- Quest cross-refs (chain + giver/turn_in) ---
	var npc_id_set := {}
	for base in npc_ids:
		npc_id_set[npc_ids[base]] = true
	var bad_quest_refs: Array = []
	for base in quest_ids:
		var txt := _file_text("data/quests", base)
		var qid := str(quest_ids[base])
		for line in txt.split("\n"):
			var t := line.strip_edges()
			if t.begins_with("giver_npc_id = \"") and t != "giver_npc_id = \"\"":
				var v := t.trim_prefix("giver_npc_id = \"").trim_suffix("\"")
				if not npc_id_set.has(v):
					bad_quest_refs.append("%s giver -> %s" % [qid, v])
			elif t.begins_with("turn_in_npc_id = \"") and t != "turn_in_npc_id = \"\"":
				var v2 := t.trim_prefix("turn_in_npc_id = \"").trim_suffix("\"")
				if not npc_id_set.has(v2):
					bad_quest_refs.append("%s turn_in -> %s" % [qid, v2])
			elif t.begins_with("next_quest_id = \"") and t != "next_quest_id = \"\"":
				var v3 := t.trim_prefix("next_quest_id = \"").trim_suffix("\"")
				if not quest_ids.values().has(v3):
					bad_quest_refs.append("%s next -> %s" % [qid, v3])
			elif t.begins_with("required_quests = [") and t != "required_quests = []":
				for req in t.trim_prefix("required_quests = [").trim_suffix("]").split(","):
					var rv := req.strip_edges().trim_prefix("\"").trim_suffix("\"")
					if rv != "" and not quest_ids.values().has(rv):
						bad_quest_refs.append("%s requires missing %s" % [qid, rv])
	if bad_quest_refs.is_empty():
		_ok("Quest chain + giver/turn_in refs all resolve")
	else:
		_fail("Phantom quest refs: %s" % ", ".join(bad_quest_refs))

	# --- Quest objective integrity ---
	# Every objective's target must resolve against the SAME catalog its
	# credit bridge reads. A KILL objective with a non-enemy target (the old
	# "glide 300 meters" Wings Over Haven bug) is a quest that can never
	# tick; the same class hit the Awakening's TALK target.
	var enemy_names := _load_display_names("data/enemies")
	# The marshal's trial dummies are entity-free and fabricated at bout
	# time (BoutHostService.TRIAL_DUMMY_NAME), so they are not in data/enemies.
	enemy_names["marshal's dummies"] = true
	var item_names := _load_display_names("data/items")
	for extra_dir in ["data/misc", "data/accessories", "data/resources"]:
		for dn in _load_display_names(extra_dir):
			item_names[dn] = true
	var ocean_ids := _load_ids("data/oceans")
	var ocean_id_set := {}
	for ob in ocean_ids:
		ocean_id_set[ocean_ids[ob]] = true
	var bad_objectives: Array = []
	for base in quest_ids:
		var qtxt := _file_text("data/quests", base)
		var qqid := str(quest_ids[base])
		# Scan EVERY line: objectives are authored inline (one line) or as a
		# multi-line array (quest_intro_core_npcs), so keying off the
		# "objectives = [" line alone would skip the multi-line form. The
		# objective regex needs a numeric "type" + a "target", which the
		# rewards dicts (string type, no target) never match.
		for line in qtxt.split("\n"):
			var tl := line.strip_edges()
			if not tl.begins_with("{"):
				continue
			for om in _objective_regex().search_all(tl):
				var otype := int(om.get_string(1))
				var otarget := om.get_string(2)
				var why := ""
				match otype:
					0:
						if not enemy_names.has(otarget):
							why = "KILL target is not an enemy display_name"
					1:
						if not item_names.has(otarget):
							why = "COLLECT target is not an item display_name"
					4:
						if not zone_id_set.has(otarget):
							why = "EXPLORE target is not a zone id"
					5:
						if not npc_id_set.has(otarget):
							why = "TALK target is not an npc_ id"
					11:
						if otarget != "sky_insight":
							why = "RECORD_INSIGHT target must be 'sky_insight'"
					12:
						if not ocean_id_set.has(otarget):
							why = "SWIM target is not an ocean id"
					13:
						if otarget != "glide_distance":
							why = "GLIDE target must be 'glide_distance'"
				if why != "":
					bad_objectives.append("%s: %s (%s)" % [qqid, why, otarget])
	if bad_objectives.is_empty():
		_ok("Quest objectives all resolve against their credit catalogs")
	else:
		_fail("Unresolvable quest objectives: %s" % "; ".join(bad_objectives))

	# --- Offering quest_ids + dialogue npc_id refs ---
	var bad_offering_refs: Array = []
	var odir := DirAccess.open("res://data/npc_offerings")
	if odir != null:
		odir.list_dir_begin()
		var of := odir.get_next()
		while of != "":
			if of.ends_with(".tres"):
				var otxt := FileAccess.get_file_as_string("res://data/npc_offerings/" + of)
				for line in otxt.split("\n"):
					var t := line.strip_edges()
					if t.begins_with("quest_ids = [") and t != "quest_ids = []":
						for qref in t.trim_prefix("quest_ids = [").trim_suffix("]").split(","):
							var qv := qref.strip_edges().trim_prefix("\"").trim_suffix("\"")
							if qv != "" and not quest_ids.values().has(qv):
								bad_offering_refs.append("%s -> %s" % [of, qv])
			of = odir.get_next()
	if bad_offering_refs.is_empty():
		_ok("Offering quest_ids all resolve")
	else:
		_fail("Phantom offering quest refs: %s" % ", ".join(bad_offering_refs))

	# --- NPC inline quest includes: shape + refs ---
	# The inline quest include shape is {"type": "quest", "quest_ids": [...]}.
	# A ref-based "quest" entry ({"type": "quest", "ref_id": ...}) is wrong:
	# the loader never reads a ref_id on a quest include, so the hook is dead
	# (npc_blacksmith_village shipped one). Every named quest id must resolve.
	var bad_quest_includes: Array = []
	for base in npc_ids:
		var ntxt := _file_text("data/npc", base)
		if not ntxt.contains("\"type\": \"quest\""):
			continue
		var qids := _quest_ids_in(ntxt)
		if qids.is_empty():
			bad_quest_includes.append("%s (quest include has no quest_ids)" % str(npc_ids[base]))
			continue
		for qv in qids:
			if not quest_ids.values().has(qv):
				bad_quest_includes.append("%s -> %s" % [str(npc_ids[base]), qv])
	if bad_quest_includes.is_empty():
		_ok("NPC inline quest includes use quest_ids and resolve")
	else:
		_fail("Bad NPC quest includes: %s" % ", ".join(bad_quest_includes))

	# --- Quest reachability: every MAIN/SIDE quest is offered by some NPC ---
	# A quest no NPC offers can never be accepted -- the includes graph (inline
	# quest_ids + referenced quest-type offerings) is the real offer surface;
	# QuestData.giver_npc_id is decorative (read nowhere). Auto-accepted quests
	# are exempt (globe_world._accept_starter_quests).
	var auto_accepted := {"quest_main_awakening": true, "quest_watch_the_sky": true}
	var offered := {}
	for base in npc_ids:
		var ntxt2 := _file_text("data/npc", base)
		for qv in _quest_ids_in(ntxt2):
			offered[qv] = true
		var rparts := ntxt2.split("\"ref_id\": \"")
		for i in range(1, rparts.size()):
			var rid2 := rparts[i].split("\"")[0]
			var opath := "res://data/npc_offerings/%s.tres" % rid2
			if not FileAccess.file_exists(opath):
				continue
			var otxt := FileAccess.get_file_as_string(opath)
			if not otxt.contains("type = \"quest\""):
				continue
			for qv in _quest_ids_in(otxt):
				offered[qv] = true
	var unreachable: Array = []
	for base in quest_ids:
		var qid := str(quest_ids[base])
		if auto_accepted.has(qid):
			continue
		var qtxt := _file_text("data/quests", base)
		var qtype := -1
		for line in qtxt.split("\n"):
			var t3 := line.strip_edges()
			if t3.begins_with("quest_type = "):
				qtype = int(t3.trim_prefix("quest_type = "))
				break
		if (qtype == 0 or qtype == 1) and not offered.has(qid):
			unreachable.append(qid)
	if unreachable.is_empty():
		_ok("Every MAIN/SIDE quest is offered by some NPC")
	else:
		_fail("Unreachable MAIN/SIDE quests: %s" % ", ".join(unreachable))

	var bad_dialogue_refs: Array = []
	for base in dialogue_ids:
		var dtxt := _file_text("data/dialogues", base)
		for line in dtxt.split("\n"):
			var t := line.strip_edges()
			if t.begins_with("npc_id = \"") and t != "npc_id = \"\"":
				var v := t.trim_prefix("npc_id = \"").trim_suffix("\"")
				if not npc_id_set.has(v):
					bad_dialogue_refs.append("%s -> %s" % [base, v])
	if bad_dialogue_refs.is_empty():
		_ok("Dialogue npc_id refs all resolve")
	else:
		_fail("Phantom dialogue npc refs: %s" % ", ".join(bad_dialogue_refs))

	# --- Zone rosters reference real NPC ids ---
	var bad_rosters: Array = []
	for base in zone_ids:
		var ztxt := _file_text("data/zones", base)
		for line in ztxt.split("\n"):
			var t := line.strip_edges()
			if t.begins_with("npcs = [") and t != "npcs = []":
				for nref in t.trim_prefix("npcs = [").trim_suffix("]").split(","):
					var nv := nref.strip_edges().trim_prefix("\"").trim_suffix("\"")
					if nv != "" and not npc_id_set.has(nv):
						bad_rosters.append("%s -> %s" % [base, nv])
	if bad_rosters.is_empty():
		_ok("Zone npc rosters all resolve")
	else:
		_fail("Phantom roster npcs: %s" % ", ".join(bad_rosters))

	# --- Gateway cross-refs (zone ids + reverse gateway id) ---
	var gateway_files: Array = []
	var gdir := DirAccess.open("res://data/gateways")
	if gdir != null:
		gdir.list_dir_begin()
		var gf := gdir.get_next()
		while gf != "":
			if gf.ends_with(".tres"):
				gateway_files.append(gf.trim_suffix(".tres"))
			gf = gdir.get_next()
	var bad_gateway_refs: Array = []
	for gbase in gateway_files:
		var gtxt := _file_text("data/gateways", gbase)
		for line in gtxt.split("\n"):
			var t := line.strip_edges()
			if t.begins_with("source_zone_id = \"") or t.begins_with("destination_zone_id = \""):
				var zref := t.substr(t.find("\"") + 1)
				zref = zref.trim_suffix("\"")
				if zref != "" and not zone_id_set.has(zref):
					bad_gateway_refs.append("%s -> %s" % [gbase, zref])
			elif t.begins_with("reverse_gateway_id = \"") and t != "reverse_gateway_id = \"\"":
				var rref := t.trim_prefix("reverse_gateway_id = \"").trim_suffix("\"")
				if not gateway_files.has(rref):
					bad_gateway_refs.append("%s reverse -> %s" % [gbase, rref])
	if bad_gateway_refs.is_empty():
		_ok("Gateway zone/reverse refs all resolve (%d gateways)" % gateway_files.size())
	else:
		_fail("Phantom gateway refs: %s" % ", ".join(bad_gateway_refs))

	# --- New economy/transport categories ---
	var currency_ids := _load_ids("data/currencies")
	var mount_ids := _load_ids("data/mounts")
	var vehicle_ids := _load_ids("data/vehicles")
	_has_prefix(currency_ids, "currency_", "Currencies")
	_has_prefix(mount_ids, "mount_", "Mounts")
	_has_prefix(vehicle_ids, "veh_", "Vehicles")

	# --- Content packs (Phase 3.2): pack_ prefix, filename == id ---
	var pack_ids := _load_ids("data/content_packs")
	_has_prefix(pack_ids, "pack_", "Content packs")

	# Currency refs on mounts/vehicles must resolve.
	var currency_id_set := {}
	for cb in currency_ids:
		currency_id_set[currency_ids[cb]] = true
	var faction_id_set := {}
	for fb in faction_ids:
		faction_id_set[faction_ids[fb]] = true
	var bad_cost_refs: Array = []
	for mbase in mount_ids:
		var mtxt := _file_text("data/mounts", mbase)
		for line in mtxt.split("\n"):
			var t := line.strip_edges()
			if t.begins_with("currency_id = \"") and t != "currency_id = \"\"":
				var cv := t.trim_prefix("currency_id = \"").trim_suffix("\"")
				if not currency_id_set.has(cv):
					bad_cost_refs.append("%s -> %s" % [str(mount_ids[mbase]), cv])
			elif t.begins_with("faction_id = \"") and t != "faction_id = \"\"" and mtxt.begins_with("[gd_resource") and mtxt.contains("MountData"):
				var fv := t.trim_prefix("faction_id = \"").trim_suffix("\"")
				if not faction_id_set.has(fv):
					bad_cost_refs.append("%s faction -> %s" % [str(mount_ids[mbase]), fv])
	for vbase in vehicle_ids:
		var vtxt := _file_text("data/vehicles", vbase)
		for line in vtxt.split("\n"):
			var t2 := line.strip_edges()
			if t2.begins_with("currency_id = \"") and t2 != "currency_id = \"\"":
				var cv2 := t2.trim_prefix("currency_id = \"").trim_suffix("\"")
				if not currency_id_set.has(cv2):
					bad_cost_refs.append("%s -> %s" % [str(vehicle_ids[vbase]), cv2])
			elif t2.begins_with("route_gateways = [") and t2 != "route_gateways = []":
				for gref in t2.trim_prefix("route_gateways = [").trim_suffix("]").split(","):
					var gv := gref.strip_edges().trim_prefix("\"").trim_suffix("\"")
					if gv != "" and not gateway_files.has(gv):
						bad_cost_refs.append("%s route -> %s" % [str(vehicle_ids[vbase]), gv])
	if bad_cost_refs.is_empty():
		_ok("Mount/vehicle currency+faction+route refs all resolve")
	else:
		_fail("Phantom cost refs: %s" % ", ".join(bad_cost_refs))

	# --- Quest items carry a resolvable quest_id ---
	var quest_id_set := {}
	for qb in quest_ids:
		quest_id_set[quest_ids[qb]] = true
	var bad_quest_items: Array = []
	for item_dir in ["data/misc", "data/accessories"]:
		var idir := DirAccess.open("res://" + item_dir)
		if idir == null:
			continue
		idir.list_dir_begin()
		var iff := idir.get_next()
		while iff != "":
			if iff.ends_with(".tres"):
				var itxt := FileAccess.get_file_as_string("res://%s/%s" % [item_dir, iff])
				if itxt.contains("is_quest_item = true"):
					var found_qid := ""
					for line in itxt.split("\n"):
						var t3 := line.strip_edges()
						if t3.begins_with("quest_id = \"") and t3 != "quest_id = \"\"":
							found_qid = t3.trim_prefix("quest_id = \"").trim_suffix("\"")
							break
					if found_qid == "" or not quest_id_set.has(found_qid):
						bad_quest_items.append("%s/%s -> %s" % [item_dir, iff, found_qid if found_qid != "" else "<none>"])
			iff = idir.get_next()
	if bad_quest_items.is_empty():
		_ok("Quest items all carry resolvable quest_id refs")
	else:
		_fail("Phantom quest-item refs: %s" % ", ".join(bad_quest_items))

	# --- Items (data/items): item_ prefix, quest items item_quest_* ---
	var item_ids := _load_ids("data/items")
	var bad_items: Array = []
	for ib in item_ids:
		var iid := str(item_ids[ib])
		if not iid.begins_with("item_"):
			bad_items.append(iid)
		if ib != iid:
			bad_items.append("%s (filename mismatch: %s.tres)" % [iid, ib])
		if iid.begins_with("item_quest_"):
			var itxt := _file_text("data/items", ib)
			if not itxt.contains("is_quest_item = true"):
				bad_items.append("%s named item_quest_* but not flagged is_quest_item" % iid)
	if bad_items.is_empty():
		_ok("Items (misc): all %d ids use 'item_' prefix, filename == id" % item_ids.size())
	else:
		_fail("Item style violations: %s" % ", ".join(bad_items))

	# --- Model/scene path integrity across ALL data files ---
	var bad_model_paths: Array = []
	for data_dir in ["data/npc", "data/enemies", "data/species", "data/mounts", "data/vehicles", "data/dwellings", "data/gateways", "data/classes"]:
		var mdir := DirAccess.open("res://" + data_dir)
		if mdir == null:
			continue
		mdir.list_dir_begin()
		var mf := mdir.get_next()
		while mf != "":
			if mf.ends_with(".tres"):
				var mtxt := FileAccess.get_file_as_string("res://%s/%s" % [data_dir, mf])
				for line in mtxt.split("\n"):
					var t := line.strip_edges()
					if t.begins_with("model_path = \"") or t.begins_with("scene_path = \""):
						var p := t.substr(t.find("res://"))
						p = p.trim_suffix("\"")
						if p.begins_with("res://") and p != "res://":
							var fs_path := p.trim_prefix("res://")
							if not FileAccess.file_exists(fs_path):
								bad_model_paths.append("%s/%s -> %s" % [data_dir, mf, p])
			mf = mdir.get_next()
	if bad_model_paths.is_empty():
		_ok("All model_path/scene_path refs resolve to real files")
	else:
		_fail("Phantom model refs: %s" % ", ".join(bad_model_paths))

	# --- Hitbox profiles: hitbox_ prefix, filename == id ---
	var hitbox_ids := _load_ids("data/hitbox_profiles")
	var bad_hitboxes: Array = []
	for hb in hitbox_ids:
		var hid := str(hitbox_ids[hb])
		if not hid.begins_with("hitbox_"):
			bad_hitboxes.append(hid)
		if hb != hid:
			bad_hitboxes.append("%s (filename mismatch: %s.tres)" % [hid, hb])
	if bad_hitboxes.is_empty():
		_ok("Hitbox profiles: all %d ids use 'hitbox_' prefix, filename == id" % hitbox_ids.size())
	else:
		_fail("Hitbox profile style violations: %s" % ", ".join(bad_hitboxes))

	# --- Hitbox profile refs resolve (enemies + npcs + species) ---
	var bad_hitbox_refs: Array = []
	for hb_dir in ["data/enemies", "data/npc", "data/species"]:
		var hdir := DirAccess.open("res://" + hb_dir)
		if hdir == null:
			continue
		hdir.list_dir_begin()
		var hf := hdir.get_next()
		while hf != "":
			if hf.ends_with(".tres"):
				var htxt := FileAccess.get_file_as_string("res://%s/%s" % [hb_dir, hf])
				for line in htxt.split("\n"):
					if line.begins_with("hitbox_profile_id = \"") and not line.begins_with("hitbox_profile_id = \"\""):
						var hv := line.strip_edges().trim_prefix("hitbox_profile_id = \"").trim_suffix("\"")
						if not hitbox_ids.values().has(hv):
							bad_hitbox_refs.append("%s/%s -> %s" % [hb_dir, hf, hv])
			hf = hdir.get_next()
	if bad_hitbox_refs.is_empty():
		_ok("Hitbox profile refs all resolve")
	else:
		_fail("Phantom hitbox profile refs: %s" % ", ".join(bad_hitbox_refs))

	# --- SPECIES HITBOX FAIRNESS RULE: playable species share ONE hitbox ---
	# Every species without a GM/agent-only marker must reference the same
	# hitbox profile (or none, which resolves to the shared default).
	var fair_profile := ""
	var unfair_species: Array = []
	var seen_species := 0
	var sdir := DirAccess.open("res://data/species")
	if sdir != null:
		sdir.list_dir_begin()
		var sf := sdir.get_next()
		while sf != "":
			# NOTE: advance the iterator BEFORE any skip logic -- a `continue`
			# below the get_next() would infinite-loop (real 120s-timeout bug).
			var fname := sf
			sf = sdir.get_next()
			if not fname.ends_with(".tres"):
				continue
			seen_species += 1
			var stxt := FileAccess.get_file_as_string("res://data/species/%s" % fname)
			var req := ""
			for line in stxt.split("\n"):
				if line.begins_with("hitbox_profile_id = \""):
					req = line.strip_edges().trim_prefix("hitbox_profile_id = \"").trim_suffix("\"")
					break
			if req == "":
				continue  # empty = shared default, always fair
			if fair_profile == "":
				fair_profile = req
			elif req != fair_profile:
				unfair_species.append("%s wants %s (group: %s)" % [fname, req, fair_profile])
	if unfair_species.is_empty():
		_ok("Species hitbox fairness: %d species share one profile (%s)" % [seen_species, fair_profile if fair_profile != "" else "default"])
	else:
		_fail("Species hitbox fairness violations: %s" % ", ".join(unfair_species))

	# --- Sky Signs: sign_ prefix, filename == id ---
	var sign_ids := _load_ids("data/signs")
	var bad_signs: Array = []
	for sb in sign_ids:
		var sid := str(sign_ids[sb])
		if not sid.begins_with("sign_"):
			bad_signs.append(sid)
		if sb != sid:
			bad_signs.append("%s (filename mismatch: %s.tres)" % [sid, sb])
		if _file_text("data/signs", sb).strip_edges() == "" or not _file_text("data/signs", sb).contains("glyph ="):
			bad_signs.append("%s (missing glyph)" % sid)
	if bad_signs.is_empty():
		_ok("Sky Signs: all %d ids use 'sign_' prefix, filename == id, glyph present" % sign_ids.size())
	else:
		_fail("Sky Sign style violations: %s" % ", ".join(bad_signs))

	# --- Acts of the Concord Chronicle: act_ prefix, filename == id ---
	var act_ids := _load_ids("data/acts")
	var bad_acts: Array = []
	for ab in act_ids:
		var aid := str(act_ids[ab])
		if not aid.begins_with("act_"):
			bad_acts.append(aid)
		if ab != aid:
			bad_acts.append("%s (filename mismatch: %s.tres)" % [aid, ab])
		if not _file_text("data/acts", ab).contains("chapters = ["):
			bad_acts.append("%s (missing chapters)" % aid)
	if bad_acts.is_empty():
		_ok("Acts: all %d ids use 'act_' prefix, filename == id, chapters present" % act_ids.size())
	else:
		_fail("Act style violations: %s" % ", ".join(bad_acts))

	# --- Chronicle mysteries: mystery_ prefix, filename == id, gated ---
	var mystery_ids := _load_ids("data/mysteries")
	var bad_mysteries: Array = []
	var act_id_set: Dictionary = {}
	for act_base in act_ids:
		act_id_set[str(act_ids[act_base])] = true
	var title_id_set: Dictionary = {}
	for title_base in _load_ids("data/titles"):
		var tid := str(_load_ids("data/titles")[title_base])
		title_id_set[tid] = true
	for mb in mystery_ids:
		var mid := str(mystery_ids[mb])
		if not mid.begins_with("mystery_"):
			bad_mysteries.append(mid)
		if mb != mid:
			bad_mysteries.append("%s (filename mismatch: %s.tres)" % [mid, mb])
		var mtxt := _file_text("data/mysteries", mb)
		var gate_act := ""
		var reward_title := ""
		for line in mtxt.split("\n"):
			var t := line.strip_edges()
			if t.begins_with("gate_act_id = \"") and t != "gate_act_id = \"\"":
				gate_act = t.trim_prefix("gate_act_id = \"").trim_suffix("\"")
			elif t.begins_with("reward_title_id = \"") and t != "reward_title_id = \"\"":
				reward_title = t.trim_prefix("reward_title_id = \"").trim_suffix("\"")
		if gate_act != "" and not act_id_set.has(gate_act):
			bad_mysteries.append("%s gate -> missing act %s" % [mid, gate_act])
		if reward_title != "" and not title_id_set.has(reward_title):
			bad_mysteries.append("%s reward -> missing title %s" % [mid, reward_title])
	if bad_mysteries.is_empty():
		_ok("Mysteries: all %d ids use 'mystery_' prefix, gates + title rewards resolve" % mystery_ids.size())
	else:
		_fail("Mystery style violations: %s" % ", ".join(bad_mysteries))

	# --- Skills: unique ids, filename == id, class->skill refs resolve ---
	# Skills live in data/skills/<archetype>/ and load into an id-keyed catalog,
	# so a duplicate id silently SHADOWS another skill (real bug: akkan_void_bolt
	# existed in both mage/ and bender/), and a class whose starting_skills /
	# skill_tree_unlocks name a skill that was never authored (or is owned by a
	# different class) silently grants nothing. No other check sees either bug.
	var skill_id_set := {}
	var skill_owner := {}
	var skill_dupes: Array = []
	var skill_name_mismatch: Array = []
	var sdir2 := DirAccess.open("res://data/skills")
	if sdir2 != null:
		sdir2.list_dir_begin()
		var ssub := sdir2.get_next()
		while ssub != "":
			var sub := ssub
			ssub = sdir2.get_next()
			if sub == "" or sub.begins_with("."):
				continue
			var kdir := DirAccess.open("res://data/skills/%s" % sub)
			if kdir == null:
				continue
			kdir.list_dir_begin()
			var kf := kdir.get_next()
			while kf != "":
				if kf.ends_with(".tres"):
					var ktxt := FileAccess.get_file_as_string("res://data/skills/%s/%s" % [sub, kf])
					var kid := ""
					var kowner := ""
					for line in ktxt.split("\n"):
						var lt := line.strip_edges()
						if lt.begins_with("id = \"") and kid == "":
							kid = lt.trim_prefix("id = \"").trim_suffix("\"")
						elif lt.begins_with("required_class = \""):
							kowner = lt.trim_prefix("required_class = \"").trim_suffix("\"")
					if kid == "":
						kf = kdir.get_next()
						continue
					if kid != kf.trim_suffix(".tres"):
						skill_name_mismatch.append("%s/%s -> id %s" % [sub, kf, kid])
					if skill_id_set.has(kid):
						skill_dupes.append("%s (also in %s)" % [kid, skill_id_set[kid]])
					else:
						skill_id_set[kid] = "%s/%s" % [sub, kf]
						skill_owner[kid] = kowner
				kf = kdir.get_next()
	if skill_name_mismatch.is_empty():
		_ok("Skills: all %d files named for their id" % skill_id_set.size())
	else:
		_fail("Skill filename/id mismatches: %s" % ", ".join(skill_name_mismatch))
	if skill_dupes.is_empty():
		_ok("Skills: all %d ids unique (no shadowed skill)" % skill_id_set.size())
	else:
		_fail("Duplicate skill ids (one silently shadows the other): %s" % ", ".join(skill_dupes))

	var bad_skill_refs: Array = []
	var empty_kits: Array = []
	var referenced_owned: Dictionary = {}
	var cdir2 := DirAccess.open("res://data/classes")
	if cdir2 != null:
		cdir2.list_dir_begin()
		var cf := cdir2.get_next()
		while cf != "":
			if cf.ends_with(".tres"):
				var ctxt := FileAccess.get_file_as_string("res://data/classes/%s" % cf)
				var cid2 := ""
				for line in ctxt.split("\n"):
					var ct := line.strip_edges()
					if ct.begins_with("id = \""):
						cid2 = ct.trim_prefix("id = \"").trim_suffix("\"")
						break
				var kit_refs := 0
				# Pull the bracketed value of each ref key (single-line or multi-line)
				# so quoted ids elsewhere (e.g. can_use_armor) never leak in.
				for key in ["starting_skills", "skill_tree_unlocks"]:
					var block := _bracket_block(ctxt, key)
					if block == "":
						continue
					for m2 in _skill_ref_regex().search_all(block):
						var ref := m2.get_string(1)
						kit_refs += 1
						referenced_owned[ref] = true
						if not skill_id_set.has(ref):
							bad_skill_refs.append("%s -> missing skill %s" % [cid2, ref])
						elif skill_owner.get(ref, "") not in ["", cid2]:
							bad_skill_refs.append("%s -> %s (owned by %s)" % [cid2, ref, skill_owner.get(ref, "")])
				# GM classes are admin-only and never appear on the select
				# screen, so an empty kit there is by design.
				if kit_refs == 0 and not cid2.begins_with("gm_"):
					empty_kits.append(cid2)
			cf = cdir2.get_next()
	if bad_skill_refs.is_empty():
		_ok("Class skill refs all resolve to a skill owned by that class")
	else:
		_fail("Dangling/cross-class skill refs: %s" % ", ".join(bad_skill_refs))

	# Six playable classes shipped with EMPTY starting_skills and
	# skill_tree_unlocks -- they could cast nothing but their basic attack.
	# A playable class must have a real kit; GM classes are exempt.
	if empty_kits.is_empty():
		_ok("Every playable class has a non-empty skill kit")
	else:
		_fail("Playable classes with an empty kit: %s" % ", ".join(empty_kits))

	# General skills: the class-agnostic verbs every class starts with.
	# They are the ONLY skills allowed to carry no required_class (a class
	# tag would hide them from every other class).
	var untagged: Array = []
	var stray_untagged: Array = []
	var genskill_dir := DirAccess.open("res://data/skills/general")
	var general_ids: Array = []
	if genskill_dir != null:
		genskill_dir.list_dir_begin()
		var genskill_file := genskill_dir.get_next()
		while genskill_file != "":
			if genskill_file.ends_with(".tres"):
				general_ids.append(genskill_file.trim_suffix(".tres"))
			genskill_file = genskill_dir.get_next()
	for sid in skill_id_set.keys():
		if skill_owner.get(sid, "") == "":
			untagged.append(sid)
			if not str(sid).begins_with("general_"):
				stray_untagged.append(sid)
	if stray_untagged.is_empty():
		_ok("Every untagged skill is a general_* shared skill (%d)" % untagged.size())
	else:
		_fail("Untagged skills that are not general_* (tag their class): %s" % ", ".join(stray_untagged))
	if general_ids.is_empty():
		_fail("No general_* skills authored (every class needs the shared verbs)")
	else:
		_ok("General shared skills present (%d): %s" % [general_ids.size(), ", ".join(general_ids)])

	# Orphan budget: a class-OWNED skill that no class kit references is
	# dead data (authored, tagged, unreachable). Must stay zero.
	var orphans: Array = []
	for sid in skill_id_set.keys():
		if skill_owner.get(sid, "") == "":
			continue
		if not referenced_owned.has(sid):
			orphans.append(sid)
	if orphans.is_empty():
		_ok("No class-owned skill is orphaned (all reachable via a class kit)")
	else:
		_fail("Class-owned skills referenced by no class: %s" % ", ".join(orphans))

	# --- Every offering NPC has a voice (no silent statue with a menu) ---
	# An NPC that offers something (vendor / service / bank / quest / dialogue
	# ref) but carries no dialogue include is a statue: the action menu shows
	# Talk with nothing behind it. Every offering NPC must author a dialogue_id.
	var mute_offerers: Array = []
	for base in npc_ids:
		var ntxt3 := _file_text("data/npc", base)
		if not ntxt3.contains("includes = ["):
			continue
		var has_offer := ntxt3.contains("\"type\": \"offering\"") \
			or ntxt3.contains("\"type\": \"vendor\"") \
			or ntxt3.contains("\"type\": \"service\"") \
			or ntxt3.contains("\"type\": \"bank\"") \
			or ntxt3.contains("\"type\": \"quest\"")
		if has_offer and not ntxt3.contains("\"type\": \"dialogue\""):
			mute_offerers.append(str(npc_ids[base]))
	if mute_offerers.is_empty():
		_ok("Every offering NPC has a dialogue include (no mute statues)")
	else:
		_fail("Offering NPCs with no dialogue include: %s" % ", ".join(mute_offerers))

	# --- Dialogue integrity: node links resolve, a farewell branch exists,
	# and every action hook names a real resource ---
	# The action enum numbers are frozen in dialogue_data.gd: GIVE_QUEST=1,
	# OPEN_SHOP=6, OPEN_VAULT=7, TEACH_SKILL=14. A hook that names a phantom
	# quest/shop/skill reports success and grants nothing -- the dead-hook bug
	# class the blacksmith's quest include shipped with.
	var offering_keys := {}
	var offdir := DirAccess.open("res://data/npc_offerings")
	if offdir != null:
		offdir.list_dir_begin()
		var ofk := offdir.get_next()
		while ofk != "":
			if ofk.ends_with(".tres"):
				offering_keys[ofk.trim_suffix(".tres")] = true
			ofk = offdir.get_next()
	var bad_dialogue_links: Array = []
	var no_farewell: Array = []
	var bad_dialogue_actions: Array = []
	var dlg_node_re := RegEx.new()
	dlg_node_re.compile("next_node\\\"?\\s*[:=]\\s*(-?\\d+)")
	var dlg_act_re := RegEx.new()
	dlg_act_re.compile("action_type\\\"?\\s*[:=]\\s*(\\d+)")
	var dlg_quest_re := RegEx.new()
	dlg_quest_re.compile("quest_id\\\"?\\s*[:=]\\s*\\\"([^\\\"]+)\\\"")
	var dlg_shop_re := RegEx.new()
	dlg_shop_re.compile("shop_id\\\"?\\s*[:=]\\s*\\\"([^\\\"]+)\\\"")
	var dlg_skill_re := RegEx.new()
	dlg_skill_re.compile("skill_id\\\"?\\s*[:=]\\s*\\\"([^\\\"]+)\\\"")
	for base in dialogue_ids:
		var dtxt2 := _file_text("data/dialogues", base)
		var did := str(dialogue_ids[base])
		# Count top-level nodes by their "speaker" keys (one per node dict).
		var node_count := dtxt2.count("\"speaker\":")
		var links: Array = []
		for m in dlg_node_re.search_all(dtxt2):
			links.append(int(m.get_string(1)))
		var has_terminal := false
		for nxt in links:
			if nxt == -1:
				has_terminal = true
			elif nxt < 0 or nxt >= node_count:
				bad_dialogue_links.append("%s -> node %d (of %d)" % [did, nxt, node_count])
		if not has_terminal:
			no_farewell.append(did)
		# Action hooks: pair each action_type with the ids on the same line.
		for line in dtxt2.split("\n"):
			if not line.contains("action_type"):
				continue
			var am := dlg_act_re.search(line)
			if am == null:
				continue
			var atype := int(am.get_string(1))
			if atype == 1:
				var qm := dlg_quest_re.search(line)
				if qm == null or not quest_ids.values().has(qm.get_string(1)):
					bad_dialogue_actions.append("%s GIVE_QUEST -> %s" % [did, qm.get_string(1) if qm != null else "(no quest_id)"])
			elif atype == 6:
				var sm := dlg_shop_re.search(line)
				if sm == null or not offering_keys.has(sm.get_string(1)):
					bad_dialogue_actions.append("%s OPEN_SHOP -> %s" % [did, sm.get_string(1) if sm != null else "(no shop_id)"])
			elif atype == 14:
				var km := dlg_skill_re.search(line)
				if km == null or not skill_id_set.has(km.get_string(1)):
					bad_dialogue_actions.append("%s TEACH_SKILL -> %s" % [did, km.get_string(1) if km != null else "(no skill_id)"])
	if bad_dialogue_links.is_empty():
		_ok("Dialogue node links all resolve within their tree")
	else:
		_fail("Dangling dialogue node links: %s" % ", ".join(bad_dialogue_links))
	if no_farewell.is_empty():
		_ok("Every dialogue tree has a farewell (-1) branch")
	else:
		_fail("Dialogue trees with no farewell branch: %s" % ", ".join(no_farewell))
	if bad_dialogue_actions.is_empty():
		_ok("Dialogue action hooks (quest/shop/skill) all resolve")
	else:
		_fail("Unresolvable dialogue action hooks: %s" % ", ".join(bad_dialogue_actions))

	_finish()
