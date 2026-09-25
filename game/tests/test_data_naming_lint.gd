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
##   - achievement title_reward must exist
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
## an `id = "..."` line (offerings have none and are skipped).
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

	_finish()
