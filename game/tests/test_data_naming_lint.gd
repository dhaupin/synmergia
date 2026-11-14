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
##   - Achievement title_reward must name an existing title
##   - Title unlock_source (achievement/quest) must exist; title ids are bare
##   - Acts: act_ prefix, filename == id, chapters present
##   - Canon spelling: the Bloom woods are "Gloamwood" (no "Gloomwood") in data
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


## The body of a .tres after the [resource] header (empty if none).
func _resource_body(txt: String) -> String:
	var i := txt.find("[resource]")
	if i < 0:
		return ""
	return txt.substr(i + "[resource]".length())


## 0-based line index of the [resource] header (-1 if absent).
func _resource_line(txt: String) -> int:
	var i := txt.find("[resource]")
	if i < 0:
		return -1
	return txt.substr(0, i).count("\n")


## A depth-0 `"key": value` line -- a dict-pair that Godot silently drops when it
## sits outside any dict/array literal.
func _stray_pair_re() -> RegEx:
	var re := RegEx.new()
	re.compile("^\"[A-Za-z_][A-Za-z0-9_]*\"\\s*:")
	return re


## The schema script a .tres names, as a res-relative path (no "res://"), so it
## lines up with _gd_paths_under keys.
func _schema_path_re() -> RegEx:
	var re := RegEx.new()
	re.compile("path=\"res://(core/schemas/[A-Za-z0-9_/]*\\.gd)\"")
	return re


## A depth-0 `key =` assignment in a .tres body.
func _top_key_re() -> RegEx:
	var re := RegEx.new()
	re.compile("^([A-Za-z_][A-Za-z0-9_]*)\\s*=")
	return re


## A property declaration in a schema script: `@export... var <name>` or a plain
## top-level `var <name>`. Matched at column 0 so indented locals are skipped.
## Plain vars count too -- Godot loads any declared property from a .tres
## (ContainerSchema's container_type/expansion_tier are plain vars and do load).
func _declared_field_re() -> RegEx:
	var re := RegEx.new()
	re.compile("^(?:@export\\w*(?:\\([^)]*\\))?\\s+var|var)\\s+([A-Za-z_][A-Za-z0-9_]*)")
	return re


## The text between the matching brackets of `field = [ ... ]` (open_ch "[")
## or `field = { ... }` (open_ch "{"). "" when the field is absent.
func _bracket_inner(txt: String, field: String, open_ch: String) -> String:
	var start := txt.find(field)
	if start < 0:
		return ""
	var close_ch := "]" if open_ch == "[" else "}"
	var open := txt.find(open_ch, start)
	var depth := 0
	var i := open
	while i < txt.length():
		var c := txt.substr(i, 1)
		if c == open_ch:
			depth += 1
		elif c == close_ch:
			depth -= 1
			if depth == 0:
				return txt.substr(open + 1, i - open - 1)
		i += 1
	return ""


## The string entries of a `field = [...]` array (single- or multi-line).
func _string_array_field(txt: String, field: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\"([^\"]+)\"")
	for m in re.search_all(_bracket_inner(txt, field, "[")):
		out.append(m.get_string(1))
	return out


## The keys of a `field = { ... }` dict (single- or multi-line).
func _dict_keys_field(txt: String, field: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\"([^\"]+)\"\\s*:")
	for m in re.search_all(_bracket_inner(txt, field, "{")):
		out.append(m.get_string(1))
	return out


## The int key/value pairs of a `field = { "k": v, ... }` dict.
func _dict_int_pairs_field(txt: String, field: String) -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.new()
	re.compile("\"([^\"]+)\"\\s*:\\s*(-?\\d+)")
	for m in re.search_all(_bracket_inner(txt, field, "{")):
		out[m.get_string(1)] = int(m.get_string(2))
	return out


## A single-line `field = "value"` string in a .tres body ("" if absent/empty).
func _string_field(txt: String, field: String) -> String:
	for line in txt.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("%s = \"" % field):
			return t.trim_prefix("%s = \"" % field).trim_suffix("\"")
	return ""


## DFS colouring for the achievement chain cycle check. 0=unseen, 1=on-stack,
## 2=done. A back-edge to an on-stack node is a cycle.
func _ach_cycle_dfs(aid: String, req_map: Dictionary, colour: Dictionary, bad: Array) -> void:
	colour[aid] = 1
	for rid in req_map.get(aid, []):
		if not req_map.has(rid):
			continue
		var c := int(colour.get(rid, 0))
		if c == 1:
			bad.append("cycle through %s -> %s" % [aid, rid])
		elif c == 0:
			_ach_cycle_dfs(rid, req_map, colour, bad)
	colour[aid] = 2


## Every ".gd" path under a directory (recursive), for the schema scan.
func _gd_paths_under(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://" + dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("."):
			f = dir.get_next()
			continue
		var rel := "%s/%s" % [dir_path, f]
		if dir.current_is_dir():
			out.append_array(_gd_paths_under(rel))
		elif f.ends_with(".gd"):
			out.append(rel)
		f = dir.get_next()
	return out


## Every ".tres" path under a data subdir (recursive). Used by the canon-term
## sweep so a dead display name cannot hide in a nested category folder.
func _tres_paths_under(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://" + dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("."):
			f = dir.get_next()
			continue
		var rel := "%s/%s" % [dir_path, f]
		if dir.current_is_dir():
			out.append_array(_tres_paths_under(rel))
		elif f.ends_with(".tres"):
			out.append(rel)
		f = dir.get_next()
	return out


## Every dialogue id named in a text blob by a `"dialogue_id": "..."` key
## (inline NPC includes). Mirrors _quest_ids_in for the dialogue surface.
func _dialogue_ids_in(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\\"dialogue_id\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out


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

## Find the authored .tres text for a skill id by scanning the skill dirs
## (matched on the authored `id`, not the filename, so a renamed file still
## resolves). "" when the id is unknown.
func _skill_text_by_id(skill_id: String) -> String:
	var root := DirAccess.open("res://data/skills")
	if root == null:
		return ""
	root.list_dir_begin()
	var sub := root.get_next()
	while sub != "":
		var dir_name := sub
		sub = root.get_next()
		if dir_name == "" or dir_name.begins_with("."):
			continue
		var dir := DirAccess.open("res://data/skills/%s" % dir_name)
		if dir == null:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".tres"):
				var txt := FileAccess.get_file_as_string("res://data/skills/%s/%s" % [dir_name, f])
				for line in txt.split("\n"):
					var lt := line.strip_edges()
					if lt.begins_with("id = \""):
						if lt.trim_prefix("id = \"").trim_suffix("\"") == skill_id:
							return txt
						break
			f = dir.get_next()
	return ""

## True when a skill's authored effects carry the family identity verb.
func _skill_has_verb(txt: String, verb: String) -> bool:
	var fx := _bracket_block(txt, "effects")
	match verb:
		"heal":
			return fx.contains("\"type\": \"heal\"") or fx.contains("\"type\":\"heal\"") \
				or fx.contains("\"type\": \"hot\"") or fx.contains("\"type\":\"hot\"")
		"teleport":
			if fx.contains("\"type\": \"teleport\"") or fx.contains("\"type\":\"teleport\""):
				return true
			for line in txt.split("\n"):
				var lt := line.strip_edges()
				if lt.begins_with("teleport_distance = ") and lt.to_float() > 0.0:
					return true
			return false
		"control":
			for k in ["stun", "root", "slow", "taunt", "silence", "fear", "knockback"]:
				if fx.contains(k):
					return true
			return false
		"damage":
			return fx.contains("\"type\": \"damage\"") or fx.contains("\"type\":\"damage\"")
	return false

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
	_has_prefix(_load_ids("data/houses"), "house_", "House tiers")

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

	# --- Quest chain symmetry ---
	# The authored chain is bidirectional: a quest that names the next link
	# and requires it is mirrored by that link naming it back as its
	# previous_quest_id + required_quests. A one-sided link (the Awakening
	# chain's missing back-edge) is a canon drift the resolve-only check
	# above cannot see.
	var bad_symmetry: Array = []
	var chain: Dictionary = {}
	for base in quest_ids:
		var ctxt := _file_text("data/quests", base)
		var cqid := str(quest_ids[base])
		var cnext := ""
		var cprev := ""
		for line in ctxt.split("\n"):
			var lt := line.strip_edges()
			if lt.begins_with("next_quest_id = \""):
				cnext = lt.trim_prefix("next_quest_id = \"").trim_suffix("\"")
			elif lt.begins_with("previous_quest_id = \""):
				cprev = lt.trim_prefix("previous_quest_id = \"").trim_suffix("\"")
		chain[cqid] = {"next": cnext, "prev": cprev}
	for cqid2 in chain:
		var node: Dictionary = chain[cqid2]
		var nx := str(node["next"])
		if nx != "" and chain.has(nx):
			var back: Dictionary = chain[nx]
			if str(back["prev"]) != cqid2:
				bad_symmetry.append("%s next -> %s but %s.previous_quest_id is '%s'" % [cqid2, nx, nx, str(back["prev"])])
		var pv := str(node["prev"])
		if pv != "" and chain.has(pv):
			if str((chain[pv] as Dictionary)["next"]) != cqid2:
				bad_symmetry.append("%s previous <- %s but %s.next_quest_id is '%s'" % [cqid2, pv, pv, str((chain[pv] as Dictionary)["next"])])
	if bad_symmetry.is_empty():
		_ok("Quest chain links are symmetric (next <-> previous)")
	else:
		_fail("One-sided quest chain links: %s" % "; ".join(bad_symmetry))


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
	# CRAFT objectives credit CraftingService.craft_completed with the
	# recipe id verbatim, so the target must resolve against data/recipes.
	var recipe_ids := _load_ids("data/recipes")
	var recipe_id_set := {}
	for rb in recipe_ids:
		recipe_id_set[recipe_ids[rb]] = true
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
					8:
						if not recipe_id_set.has(otarget):
							why = "CRAFT target is not a recipe id"
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

	# --- Dialogue include parity: an NPC's dialogue tree must name THAT NPC ---
	# The capital instances reused the village trees, so npc_elder_capital's
	# tree carried npc_id "npc_village_elder". DialogueService now emits the
	# live npc_id, but the AUTHORING contract still matters: a tree written
	# for one NPC offered by another is either a copy-paste or a mismatch,
	# and TALK quest credit (keyed on the NPCData id) silently mis-fires.
	var dialogue_npc: Dictionary = {}
	for base in dialogue_ids:
		var dnp := ""
		for line in _file_text("data/dialogues", base).split("\n"):
			var tl := line.strip_edges()
			if tl.begins_with("npc_id = \""):
				dnp = tl.trim_prefix("npc_id = \"").trim_suffix("\"")
				break
		dialogue_npc[str(dialogue_ids[base])] = dnp
	var dialogue_id_set := {}
	for base in dialogue_ids:
		dialogue_id_set[str(dialogue_ids[base])] = true
	var bad_dialogue_includes: Array = []
	for base in npc_ids:
		var ntxt := _file_text("data/npc", base)
		var owner := str(npc_ids[base])
		for inc_did in _dialogue_ids_in(ntxt):
			if not dialogue_id_set.has(inc_did):
				bad_dialogue_includes.append("%s -> %s (no such tree)" % [owner, inc_did])
				continue
			var tree_npc := str(dialogue_npc.get(inc_did, ""))
			if tree_npc != "" and tree_npc != owner:
				bad_dialogue_includes.append("%s -> %s (tree npc_id=%s)" % [owner, inc_did, tree_npc])
	if bad_dialogue_includes.is_empty():
		_ok("Every NPC dialogue include resolves and names its own NPC")
	else:
		_fail("Dialogue include parity: %s" % ", ".join(bad_dialogue_includes))

	# --- Orphan dialogue budget: an authored tree no NPC offers is dead ---
	# The mute-NPC pass authored eight trees; this keeps a future tree from
	# shipping unreferenced (the mirror of the orphan-quest reachability law).
	var referenced_dialogues := {}
	for base in npc_ids:
		for inc_did in _dialogue_ids_in(_file_text("data/npc", base)):
			referenced_dialogues[inc_did] = true
	for base in _load_ids("data/npc_offerings"):
		for inc_did in _dialogue_ids_in(_file_text("data/npc_offerings", base)):
			referenced_dialogues[inc_did] = true
	var orphan_dialogues: Array = []
	for base in dialogue_ids:
		var did := str(dialogue_ids[base])
		if not referenced_dialogues.has(did):
			orphan_dialogues.append(did)
	if orphan_dialogues.is_empty():
		_ok("No orphan dialogue trees (every tree is offered by some NPC)")
	else:
		_fail("Orphan dialogue trees (no NPC offers them): %s" % ", ".join(orphan_dialogues))

	# --- Chain reachability: a quest's next_quest_id must be offerable ---
	# The reachability pass above checks MAIN/SIDE offers; this one catches a
	# CHAIN whose sequel is authored but offered by nobody (quest_tideline_kelp
	# was the live case: the jeweler offered quest_pearl_dive but not its
	# authored next_quest_id, so the chain dead-ended).
	var bad_chains: Array = []
	for base in quest_ids:
		var qtxt2 := _file_text("data/quests", base)
		for line in qtxt2.split("\n"):
			var t4 := line.strip_edges()
			if t4.begins_with("next_quest_id = \""):
				var nxt := t4.trim_prefix("next_quest_id = \"").trim_suffix("\"")
				if nxt != "" and not offered.has(nxt) and not auto_accepted.has(nxt):
					bad_chains.append("%s -> %s" % [str(quest_ids[base]), nxt])
	if bad_chains.is_empty():
		_ok("Every quest chain target is offered by some NPC")
	else:
		_fail("Chain targets offered by nobody: %s" % ", ".join(bad_chains))

	# --- Canon terms: the capital descriptions drifted to "Federation" ---
	# Canon (labs/prd-story.md sec. 4-5) is the CONCORD; "Federation" survived
	# only in a terrain_gen comment quoting a 2026-10-14 note. Player-facing
	# .tres copy must not carry the dead term.
	var canon_banned := ["Federation"]
	var bad_canon: Array = []
	for base in npc_ids:
		var ctxt := _file_text("data/npc", base)
		for term in canon_banned:
			if ctxt.contains(term):
				bad_canon.append("%s says '%s'" % [str(npc_ids[base]), term])
	for base in quest_ids:
		var ctxt2 := _file_text("data/quests", base)
		for term in canon_banned:
			if ctxt2.contains(term):
				bad_canon.append("%s says '%s'" % [str(quest_ids[base]), term])
	for base in dialogue_ids:
		var ctxt3 := _file_text("data/dialogues", base)
		for term in canon_banned:
			if ctxt3.contains(term):
				bad_canon.append("%s says '%s'" % [base, term])
	if bad_canon.is_empty():
		_ok("NPC/quest/dialogue copy honors the canon terms (no dead names)")
	else:
		_fail("Dead canon terms in copy: %s" % ", ".join(bad_canon))

	# --- Canon spelling: the Bloom woods are "Gloamwood", never "Gloomwood" ---
	# Owner call 2026-11-28 (labs/story-landmark-names.md, prd-story.md sec. 10):
	# ids already read "gloam" (enemy_gloamwood_stalker, quest_gloamwood_ledger,
	# loot_gloam_*, res_gloam_spore); the DISPLAY strings had drifted to
	# "Gloomwood". Freeze the canon so the split cannot come back. Scans every
	# .tres in game/data (recursive) -- display text only, ids are already right.
	var gloom_hits: Array = []
	for rel in _tres_paths_under("data"):
		var gtxt := FileAccess.get_file_as_string("res://" + rel)
		if gtxt.contains("Gloomwood"):
			gloom_hits.append(rel)
	if gloom_hits.is_empty():
		_ok("Bloom woods are 'Gloamwood' everywhere in data (no 'Gloomwood')")
	else:
		_fail("'Gloomwood' spelling survives (canon is 'Gloamwood'): %s" % ", ".join(gloom_hits))

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
	for data_dir in ["data/npc", "data/enemies", "data/species", "data/mounts", "data/vehicles", "data/furnishings", "data/houses", "data/gateways", "data/classes"]:
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

	# --- Landmarks: landmark_ prefix, filename == id, unit-length dirs, and
	# zone/gateway refs that resolve (the atlas law: identity only) ---
	var landmark_ids := _load_ids("data/landmarks")
	var bad_landmarks: Array = []
	var landmark_zone_set: Dictionary = {}
	var zone_ids_raw := _load_ids("data/zones")
	for zb in zone_ids_raw:
		landmark_zone_set[str(zone_ids_raw[zb])] = true
	var landmark_gate_set: Dictionary = {}
	var gate_ids_raw := _load_ids("data/gateways")
	for gb in gate_ids_raw:
		landmark_gate_set[str(gate_ids_raw[gb])] = true
	for lb in landmark_ids:
		var lid := str(landmark_ids[lb])
		if not lid.begins_with("landmark_"):
			bad_landmarks.append(lid)
		if lb != lid:
			bad_landmarks.append("%s (filename mismatch: %s.tres)" % [lid, lb])
		var ltxt := _file_text("data/landmarks", lb)
		var ldir := Vector3.ZERO
		var lzone := ""
		var lgw := ""
		for line in ltxt.split("\n"):
			var t := line.strip_edges()
			if t.begins_with("dir = Vector3("):
				var inner := t.trim_prefix("dir = Vector3(").trim_suffix(")")
				var parts := inner.split(",")
				if parts.size() == 3:
					ldir = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
			elif t.begins_with("zone_id = \"") and t != "zone_id = \"\"":
				lzone = t.trim_prefix("zone_id = \"").trim_suffix("\"")
			elif t.begins_with("gateway_id = \"") and t != "gateway_id = \"\"":
				lgw = t.trim_prefix("gateway_id = \"").trim_suffix("\"")
		if ldir.length_squared() > 0.000001 and absf(ldir.length() - 1.0) > 0.001:
			bad_landmarks.append("%s (dir not unit length: %.4f)" % [lid, ldir.length()])
		if lzone != "" and not landmark_zone_set.has(lzone):
			bad_landmarks.append("%s zone -> missing %s" % [lid, lzone])
		if lgw != "" and not landmark_gate_set.has(lgw):
			bad_landmarks.append("%s gateway -> missing %s" % [lid, lgw])
	if bad_landmarks.is_empty():
		_ok("Landmarks: all %d ids use 'landmark_' prefix, unit-length dirs, zone/gateway refs resolve" % landmark_ids.size())
	else:
		_fail("Landmark style violations: %s" % ", ".join(bad_landmarks))

	# --- Skills: unique ids, filename == id, class->skill refs resolve ---
	# Skills live in data/skills/<archetype>/ and load into an id-keyed catalog,
	# so a duplicate id silently SHADOWS another skill (real bug: akkan_void_bolt
	# existed in both mage/ and bender/), and a class whose starting_skills /
	# skill_tree_unlocks name a skill that was never authored (or is owned by a
	# different class) silently grants nothing. No other check sees either bug.
	var skill_id_set := {}
	var skill_owner := {}
	var skill_dupes: Array = []
	var class_skill_names := {}
	var dup_class_names: Array = []
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
					var kdisp := ""
					for line in ktxt.split("\n"):
						var lt := line.strip_edges()
						if lt.begins_with("id = \"") and kid == "":
							kid = lt.trim_prefix("id = \"").trim_suffix("\"")
						elif lt.begins_with("display_name = \""):
							kdisp = lt.trim_prefix("display_name = \"").trim_suffix("\"")
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
						if kowner != "" and kdisp != "":
							var nkey := "%s|%s" % [kowner, kdisp]
							if class_skill_names.has(nkey):
								dup_class_names.append("%s: %s (also %s)" % [kowner, kdisp, class_skill_names[nkey]])
							else:
								class_skill_names[nkey] = kid
				kf = kdir.get_next()
	if skill_name_mismatch.is_empty():
		_ok("Skills: all %d files named for their id" % skill_id_set.size())
	else:
		_fail("Skill filename/id mismatches: %s" % ", ".join(skill_name_mismatch))
	if skill_dupes.is_empty():
		_ok("Skills: all %d ids unique (no shadowed skill)" % skill_id_set.size())
	else:
		_fail("Duplicate skill ids (one silently shadows the other): %s" % ", ".join(skill_dupes))
	# A class kit is shown by name in the Skill Academy: two skills of the SAME
	# class sharing a display_name are indistinguishable to the player.
	if dup_class_names.is_empty():
		_ok("Skills: no same-class duplicate display_names")
	else:
		_fail("Same-class duplicate skill names: %s" % ", ".join(dup_class_names))

	# --- Skill buff/debuff effect_ids must resolve to a status effect ---
	# A skill's {"type": "buff"/"debuff", "effect_id": X} resolves X through
	# StatusEffectFactory -> data/status_effects/*.tres at cast time. A
	# dangling X is a silent no-op (the cast succeeds, the buff never lands)
	# -- 27 shipped this way. No other check sees it.
	var status_effect_ids := _load_ids("data/status_effects")
	var bad_effect_refs: Array = []
	var effect_ref_count := 0
	if sdir2 != null:
		sdir2.list_dir_begin()
		var esub := sdir2.get_next()
		while esub != "":
			var sub2 := esub
			esub = sdir2.get_next()
			if sub2 == "" or sub2.begins_with("."):
				continue
			var edir := DirAccess.open("res://data/skills/%s" % sub2)
			if edir == null:
				continue
			edir.list_dir_begin()
			var ef := edir.get_next()
			while ef != "":
				if ef.ends_with(".tres"):
					var etxt := FileAccess.get_file_as_string("res://data/skills/%s/%s" % [sub2, ef])
					var parts := etxt.split("\"effect_id\": \"")
					for pi in range(1, parts.size()):
						var eid := parts[pi].split("\"")[0]
						if eid == "":
							continue
						effect_ref_count += 1
						if not status_effect_ids.values().has(eid):
							bad_effect_refs.append("%s -> %s" % [ef.trim_suffix(".tres"), eid])
				ef = edir.get_next()
	if bad_effect_refs.is_empty():
		_ok("Skills: all %d buff/debuff effect_ids resolve to a status effect" % effect_ref_count)
	else:
		_fail("Phantom skill effect_id refs (silent no-op buffs): %s" % ", ".join(bad_effect_refs))

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

	# --- Achievement rewards: title_reward must name a real title ---
	# AchievementService._do_unlock routes title_reward through
	# TitleService.unlock, which WARNS and returns false on an unknown id --
	# the player completes the achievement and silently receives no title.
	# Seven defs shipped exactly this way (streaker, bloodthirsty,
	# juggernaut, unkillable, wind_rider, Hordebreaker, MVP); the header
	# promised this check but no code implemented it.
	var ach_ids := _load_ids("data/achievements")
	var title_ids_all := _load_ids("data/titles")
	var bad_ach_titles: Array = []
	var ach_title_refs: Dictionary = {}
	for ab in ach_ids:
		var atxt := _file_text("data/achievements", ab)
		var areward := ""
		for line in atxt.split("\n"):
			var lt := line.strip_edges()
			if lt.begins_with("title_reward = \"") and lt != "title_reward = \"\"":
				areward = lt.trim_prefix("title_reward = \"").trim_suffix("\"")
		if areward == "":
			continue
		ach_title_refs[areward] = str(ach_ids[ab])
		if not title_ids_all.values().has(areward):
			bad_ach_titles.append("%s title_reward -> missing title %s" % [str(ach_ids[ab]), areward])
	if bad_ach_titles.is_empty():
		_ok("Achievements: all %d title_reward refs resolve" % ach_title_refs.size())
	else:
		_fail("Achievement title rewards naming no title: %s" % ", ".join(bad_ach_titles))

	# --- Achievement chains: required_achievements must resolve and be acyclic ---
	# AchievementService._requirements_met gates a def on its required_achievements
	# (each must be unlocked first). Nothing validated them: a typo names a
	# prereq that can never unlock, and a cycle deadlocks every def in it --
	# both silently lock the achievement forever, the same two-sided-contract
	# failure as the title bug. This is the chain gate for the achievement graph.
	var ach_id_set: Array = ach_ids.values()
	var bad_reqs: Array = []
	var req_map: Dictionary = {}
	for ab in ach_ids:
		var areqs: Array = []
		var atxt2 := _file_text("data/achievements", ab)
		var rline := ""
		for line in atxt2.split("\n"):
			var lt := line.strip_edges()
			if lt.begins_with("required_achievements = ["):
				rline = lt
				break
		if rline != "":
			var inner := rline.trim_prefix("required_achievements = [").trim_suffix("]")
			for piece in inner.split(","):
				var rid := piece.strip_edges().trim_prefix("\"").trim_suffix("\"")
				if rid != "":
					areqs.append(rid)
		req_map[str(ach_ids[ab])] = areqs
		for rid in areqs:
			if not ach_id_set.has(rid):
				bad_reqs.append("%s requires unknown %s" % [str(ach_ids[ab]), rid])
			elif rid == str(ach_ids[ab]):
				bad_reqs.append("%s requires itself" % str(ach_ids[ab]))
	# Cycle detection (DFS colouring) over the resolvable edges.
	var colour: Dictionary = {}
	for aid in req_map:
		colour[aid] = 0
	for aid in req_map:
		if int(colour[aid]) == 0:
			_ach_cycle_dfs(aid, req_map, colour, bad_reqs)
	if bad_reqs.is_empty():
		_ok("Achievements: required_achievements all resolve and are acyclic")
	else:
		_fail("Bad achievement chains: %s" % ", ".join(bad_reqs))

	# --- Titles: filename == id, bare ids, and every achievement/quest
	# unlock_source names a real target ---
	# A title whose unlock_source names no achievement is unreachable: the only
	# generic grant path (AchievementService rewards) can never fire it. Quest
	# (method 1) titles name a quest or a mystery; other methods are granted by
	# routes outside the data (PvP, events, GM, purchase) and carry no source.
	var bad_title_style: Array = []
	var bad_title_sources: Array = []
	for tb in title_ids_all:
		var tid2 := str(title_ids_all[tb])
		# Enemy convention: the FILE keeps the prefix, the id stays bare
		# (title_slayer.tres carries id "slayer").
		if tb != "title_" + tid2:
			bad_title_style.append("%s (filename mismatch: %s.tres)" % [tid2, tb])
		if tid2.begins_with("title_"):
			bad_title_style.append("%s (bare id expected, no 'title_' prefix)" % tid2)
		var ttxt := _file_text("data/titles", tb)
		var tmethod := -1
		var tsource := ""
		for line in ttxt.split("\n"):
			var tt := line.strip_edges()
			if tt.begins_with("unlock_method = "):
				tmethod = int(tt.trim_prefix("unlock_method = "))
			elif tt.begins_with("unlock_source = \"") and tt != "unlock_source = \"\"":
				tsource = tt.trim_prefix("unlock_source = \"").trim_suffix("\"")
		if tsource == "":
			continue
		var src_ok := true
		if tmethod == 0:
			src_ok = ach_ids.values().has(tsource)
		elif tmethod == 1:
			src_ok = _load_ids("data/quests").values().has(tsource) \
				or tsource.begins_with("mystery_") \
				or tsource.begins_with("found_")
		if not src_ok:
			bad_title_sources.append("%s source -> %s" % [tid2, tsource])
	if bad_title_style.is_empty():
		_ok("Titles: all %d ids are bare, filename == id" % title_ids_all.size())
	else:
		_fail("Title style violations: %s" % ", ".join(bad_title_style))
	if bad_title_sources.is_empty():
		_ok("Titles: every achievement/quest unlock_source resolves")
	else:
		_fail("Titles with unresolvable unlock_source: %s" % ", ".join(bad_title_sources))

	# --- Title grant parity: an ACHIEVEMENT-method title's unlock_source
	# achievement must actually grant it ---
	# unlock_source is documentation-only (TitleService never reads it); the
	# ONLY generic grant path is AchievementService._grant_rewards routing
	# def.title_reward through TitleService.unlock. A title declaring
	# unlock_method = 0 + a real achievement source, where that achievement
	# carries no (or a different) title_reward, is unreachable forever -- the
	# same silent-null class as an unresolved title_reward, mirrored. Five
	# shipped this way (collector, explorer, slayer, social_butterfly,
	# trader). Other methods (purchase/level/playtime/GM/quest) are granted
	# outside the data and carry no unlock_source to cross-check.
	var ach_base_by_id: Dictionary = {}
	for ab2 in ach_ids:
		ach_base_by_id[str(ach_ids[ab2])] = ab2
	var bad_title_grants: Array = []
	for tb in title_ids_all:
		var tid3 := str(title_ids_all[tb])
		var gmethod := -1
		var gsource := ""
		for line in _file_text("data/titles", tb).split("\n"):
			var gt := line.strip_edges()
			if gt.begins_with("unlock_method = "):
				gmethod = int(gt.trim_prefix("unlock_method = "))
			elif gt.begins_with("unlock_source = \"") and gt != "unlock_source = \"":
				gsource = gt.trim_prefix("unlock_source = \"").trim_suffix("\"")
		if gmethod != 0 or gsource == "" or not ach_base_by_id.has(gsource):
			continue
		var src_grant := ""
		for line in _file_text("data/achievements", str(ach_base_by_id[gsource])).split("\n"):
			var st := line.strip_edges()
			if st.begins_with("title_reward = \""):
				src_grant = st.trim_prefix("title_reward = \"").trim_suffix("\"")
		if src_grant != tid3:
			bad_title_grants.append("%s source %s grants '%s'" % [tid3, gsource, src_grant])
	if bad_title_grants.is_empty():
		_ok("Titles: every ACHIEVEMENT-method title is granted by its source achievement")
	else:
		_fail("Titles never granted by their source achievement: %s" % ", ".join(bad_title_grants))
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

	# --- Stray dict-pair lines: a `"key": value,` outside any dict/array literal ---
	# Godot does NOT read `"key": value,` as a property assignment: it is a parse
	# error that silently DROPS the line (the resource still loads, the field
	# keeps its default). Eighteen class .tres carried their focal_stat_1/2 this
	# way -- some as stray top-level lines, some stuffed INSIDE the stat_growth
	# dict -- so every class's focal stats loaded empty and calculate_stat's
	# +1-per-level focal bonus silently never applied. Field-level sibling of the
	# phantom-field class (a declared field the data never really sets).
	var stray_pairs: Array = []
	for sp in _tres_paths_under("data"):
		var stxt := FileAccess.get_file_as_string("res://" + sp)
		var sbody := _resource_body(stxt)
		if sbody == "":
			continue
		var sbase := _resource_line(stxt)
		var sdepth := 0
		var slnum := 0
		for sline in sbody.split("\n"):
			slnum += 1
			var ss := sline.strip_edges()
			if sdepth == 0 and _stray_pair_re().search(ss) != null:
				stray_pairs.append("%s:%d %s" % [sp, sbase + slnum, ss])
			sdepth += ss.count("{") + ss.count("[") - ss.count("}") - ss.count("]")
	if stray_pairs.is_empty():
		_ok("No stray dict-pair lines in any .tres (a depth-0 key/value pair is a silent drop)")
	else:
		_fail("Stray dict-pair lines (fields silently dropped on load): %s" % ", ".join(stray_pairs))

	# --- Phantom fields: a top-level key no schema declares ---
	# Godot drops undeclared properties on load. A key with no @export in its
	# resource's own schema script is dead weight at best, a silently ignored
	# authoring mistake at worst (the NPC trio npc_type/shop_title/services was
	# exactly this class; K3 removed them, this freezes the result). The schema
	# is resolved from the [ext_resource] script path the .tres names -- the
	# authoritative link -- NOT the script_class label, which five shipped
	# resources carry stale (CharacterClassSchema, ContainerTypes, ...). Nested
	# dict keys (loot entry fields, stat names) are NOT checked -- depth-0 only.
	var schema_fields: Dictionary = {}
	for sch in _gd_paths_under("core/schemas"):
		var sflds: Array = []
		for sfline in FileAccess.get_file_as_string("res://" + sch).split("\n"):
			var em := _declared_field_re().search(sfline)
			if em != null:
				sflds.append(em.get_string(1))
		schema_fields[sch] = sflds
	var phantoms: Array = []
	for pp in _tres_paths_under("data"):
		var ptxt := FileAccess.get_file_as_string("res://" + pp)
		var sm := _schema_path_re().search(ptxt)
		if sm == null:
			continue
		var spath := sm.get_string(1)
		if not schema_fields.has(spath):
			continue
		var pdepth := 0
		for pline in _resource_body(ptxt).split("\n"):
			var ps := pline.strip_edges()
			if pdepth == 0:
				var km := _top_key_re().search(ps)
				if km != null and km.get_string(1) != "script" and not schema_fields[spath].has(km.get_string(1)):
					phantoms.append("%s: %s" % [pp, km.get_string(1)])
			pdepth += ps.count("{") + ps.count("[") - ps.count("}") - ps.count("]")
	if phantoms.is_empty():
		_ok("No phantom fields (every depth-0 .tres key is a declared property)")
	else:
		_fail("Phantom fields (undeclared, dropped on load): %s" % ", ".join(phantoms))

	# --- Species home_zone must name a real zone (the Akkan phantom) ---
	# character_select copies species.home_zone into CharacterData.zone_id; a
	# phantom there is a dead-end character (the lane-C bug: dark_highlands named
	# no file). The creation path now falls back, but the DATA must still be
	# sound -- author the zone or repoint the species.
	var species_ids := _load_ids("data/species")
	var bad_home_zones: Array = []
	for sb in species_ids:
		var stxt := _file_text("data/species", sb)
		var hz := _string_field(stxt, "home_zone")
		if hz != "" and not zone_id_set.has(hz):
			bad_home_zones.append("%s -> %s" % [str(species_ids[sb]), hz])
	if bad_home_zones.is_empty():
		_ok("Species home_zone refs all resolve (%d species)" % species_ids.size())
	else:
		_fail("Phantom species home_zone refs: %s" % ", ".join(bad_home_zones))

	# --- Faction relations must name real factions, symmetrically ---
	# A relation to a faction that does not exist (elf_faction/dwarf_faction were
	# both phantoms) can never resolve; and a one-sided relation makes
	# FactionManager.get_relation answer differently depending on argument order.
	var bad_relations: Array = []
	var rel_map: Dictionary = {}
	for fb3 in faction_ids:
		var fid := str(faction_ids[fb3])
		var rels := _dict_int_pairs_field(_file_text("data/factions", fb3), "relations")
		rel_map[fid] = rels
		for other in rels:
			if not faction_id_set.has(other):
				bad_relations.append("%s -> %s (phantom faction)" % [fid, other])
	for fid2 in rel_map:
		for other2 in rel_map[fid2]:
			if not faction_id_set.has(other2):
				continue
			var back: int = int(rel_map.get(other2, {}).get(fid2, 1))
			if back != int(rel_map[fid2][other2]):
				bad_relations.append("%s/%s asymmetric (%d vs %d)" % [fid2, other2, int(rel_map[fid2][other2]), back])
	if bad_relations.is_empty():
		_ok("Faction relations resolve and are symmetric (%d factions)" % faction_ids.size())
	else:
		_fail("Faction relation violations: %s" % ", ".join(bad_relations))

	# --- Species relations must name real species, symmetrically ---
	# entity_service.is_ally/is_enemy read allied_species/hostile_species by id;
	# "elf"/"dwarf" resolved to nothing. Hostility/alliance is a mutual fact:
	# if A is hostile to B, B must be hostile to A (and likewise for allies).
	var species_id_set := {}
	for sb2 in species_ids:
		species_id_set[species_ids[sb2]] = true
	var bad_species_rels: Array = []
	var allied_map: Dictionary = {}
	var hostile_map: Dictionary = {}
	for sb3 in species_ids:
		var sid := str(species_ids[sb3])
		var sstxt := _file_text("data/species", sb3)
		allied_map[sid] = _string_array_field(sstxt, "allied_species")
		hostile_map[sid] = _string_array_field(sstxt, "hostile_species")
		for ref in allied_map[sid]:
			if not species_id_set.has(ref):
				bad_species_rels.append("%s allied -> %s (phantom species)" % [sid, ref])
		for ref2 in hostile_map[sid]:
			if not species_id_set.has(ref2):
				bad_species_rels.append("%s hostile -> %s (phantom species)" % [sid, ref2])
	for sid2 in species_id_set:
		for ally in allied_map[sid2]:
			if species_id_set.has(ally) and not allied_map[ally].has(sid2):
				bad_species_rels.append("%s allied %s but not mutual" % [sid2, ally])
		for foe in hostile_map[sid2]:
			if species_id_set.has(foe) and not hostile_map[foe].has(sid2):
				bad_species_rels.append("%s hostile %s but not mutual" % [sid2, foe])
	if bad_species_rels.is_empty():
		_ok("Species relations resolve and are symmetric (%d species)" % species_ids.size())
	else:
		_fail("Species relation violations: %s" % ", ".join(bad_species_rels))

	# --- Species stat_modifiers must use real stat names ---
	# get_stat_modifier(stat) reads by name; a typo'd key ("str" for "strength")
	# is silently ignored by every reader (character_data, entity.gd). The six
	# canonical stats are the schema's own default dict keys.
	var stat_names := {}
	for dk in _dict_keys_field(FileAccess.get_file_as_string("res://core/schemas/species.gd"), "stat_modifiers"):
		stat_names[dk] = true
	var bad_stat_keys: Array = []
	for sb4 in species_ids:
		var keys := _dict_keys_field(_file_text("data/species", sb4), "stat_modifiers")
		if keys.is_empty():
			bad_stat_keys.append("%s -> no stat_modifiers" % str(species_ids[sb4]))
		for k in keys:
			if not stat_names.has(k):
				bad_stat_keys.append("%s -> %s" % [str(species_ids[sb4]), k])
	if bad_stat_keys.is_empty():
		_ok("Species stat_modifiers use the 6 canonical stat names (%d species)" % species_ids.size())
	else:
		_fail("Species stat_modifier key violations: %s" % ", ".join(bad_stat_keys))

	# --- Events (data/events): event_ prefix + reward items resolve ---
	# The EventData catalog drives the global event multipliers (EventService).
	# Its `rewards` lines name items by bare id; a typo'd id was silently inert
	# (the shipped weekend event pointed at a nonexistent token). Resolve every
	# item reward against the item-bearing data dirs.
	var event_ids := _load_ids("data/events")
	var item_id_set := {}
	for item_dir in ["data/items", "data/consumables", "data/accessories", "data/armors", "data/weapons", "data/resources"]:
		for k in _load_ids(item_dir):
			item_id_set[_load_ids(item_dir)[k]] = true
	var bad_events: Array = []
	for eb in event_ids:
		var eid := str(event_ids[eb])
		if not eid.begins_with("event_"):
			bad_events.append("%s (missing event_ prefix)" % eid)
		var etxt := _file_text("data/events", eb)
		for entry in _bracket_inner(etxt, "rewards", "[").split("}"):
			if not entry.contains("\"type\": \"item\""):
				continue
			var rid := ""
			var rm := RegEx.new()
			rm.compile("\"id\"\\s*:\\s*\"([^\"]+)\"")
			var rmm := rm.search(entry)
			if rmm != null:
				rid = rmm.get_string(1)
			if not rid.is_empty() and not item_id_set.has(rid):
				bad_events.append("%s reward -> %s (phantom item)" % [eid, rid])
	if bad_events.is_empty():
		_ok("Events: all %d ids use 'event_' prefix and reward items resolve" % event_ids.size())
	else:
		_fail("Event data violations: %s" % ", ".join(bad_events))

	# --- Skill descriptions must not promise behavior the payload lacks ---
	# A player reads the description, not the effects[] array. When the two
	# disagree the skill is a lie in the tooltip: "absorbs damage" on a skill
	# with no shield, "reflects" with no reflect, "immune to all damage" with
	# no immunity. Capability is read from the skill's own effects[] entries
	# plus the payload of every status effect it references, so an indirect
	# buff ({"effect_id": "buff_rune_ward"}) still counts.
	# [pattern, required capability, label]. Patterns are regex so "immune to
	# all slow" and "immune to slow" both satisfy the slow rule. A claim needs
	# the matching payload anywhere in the skill's own effects or a referenced
	# status effect.
	var claim_rules := [
		["absorb", "shield", "absorb"],
		["reflect", "reflect", "reflect"],
		["immune to all damage", "immune_all", "immune to all damage"],
		["immune to (all )?(stun|stuns)", "immune_stun", "immune to stun"],
		["immune to (all )?(slow|slows)", "immune_slow", "immune to slow"],
		["immune to (all )?(root|roots)", "immune_root", "immune to root"],
	]
	var effect_caps := {}
	var se_dir := DirAccess.open("res://data/status_effects")
	if se_dir != null:
		se_dir.list_dir_begin()
		var se_f := se_dir.get_next()
		while se_f != "":
			if se_f.ends_with(".tres"):
				var se_txt := FileAccess.get_file_as_string("res://data/status_effects/%s" % se_f)
				var se_id := ""
				for line in se_txt.split("\n"):
					var st := line.strip_edges()
					if st.begins_with("id = \""):
						se_id = st.trim_prefix("id = \"").trim_suffix("\"")
						break
				var caps: Array = []
				var re_shield := RegEx.new()
				re_shield.compile("(?m)^shield_amount = ([0-9.]+)")
				var m_shield := re_shield.search(se_txt)
				if m_shield != null and float(m_shield.get_string(1)) > 0.0:
					caps.append("shield")
				var re_reflect := RegEx.new()
				re_reflect.compile("(?m)^damage_reflect = ([0-9.]+)")
				var m_reflect := re_reflect.search(se_txt)
				if m_reflect != null and float(m_reflect.get_string(1)) > 0.0:
					caps.append("reflect")
				if se_txt.contains("immune_all = true"):
					caps.append("immune_all")
				# Per-tag immunity payloads, so a ward that refuses one specific
				# control (immune_stun) satisfies a matching "immune to stun" claim.
				for tag in ["stun", "slow", "root", "silence", "fear", "knockback"]:
					if se_txt.contains("immune_%s = true" % tag):
						caps.append("immune_%s" % tag)
				effect_caps[se_id] = caps
			se_f = se_dir.get_next()
	var lying: Array = []
	var skill_root2 := DirAccess.open("res://data/skills")
	if skill_root2 != null:
		skill_root2.list_dir_begin()
		var sk_sub := skill_root2.get_next()
		while sk_sub != "":
			var sub3 := sk_sub
			sk_sub = skill_root2.get_next()
			if sub3 == "" or sub3.begins_with("."):
				continue
			var sk_dir := DirAccess.open("res://data/skills/%s" % sub3)
			if sk_dir == null:
				continue
			sk_dir.list_dir_begin()
			var sk_f := sk_dir.get_next()
			while sk_f != "":
				if sk_f.ends_with(".tres"):
					var sk_txt := FileAccess.get_file_as_string("res://data/skills/%s/%s" % [sub3, sk_f])
					var sk_id := ""
					var sk_desc := ""
					var sk_effects := ""
					for line in sk_txt.split("\n"):
						var lt := line.strip_edges()
						if lt.begins_with("id = \"") and sk_id == "":
							sk_id = lt.trim_prefix("id = \"").trim_suffix("\"")
						elif lt.begins_with("description = \""):
							sk_desc = lt.to_lower()
						elif lt.begins_with("effects = "):
							sk_effects = lt.to_lower()
					var sk_caps: Array = []
					if sk_effects.contains("\"type\": \"shield\"") or sk_effects.contains("\"type\":\"shield\""):
						sk_caps.append("shield")
					for cap_ref in effect_caps:
						if sk_effects.contains("\"effect_id\": \"%s\"" % cap_ref):
							sk_caps.append_array(effect_caps[cap_ref])
					for rule in claim_rules:
						var re_claim := RegEx.new()
						re_claim.compile(str(rule[0]))
						if re_claim.search(sk_desc) != null and not sk_caps.has(rule[1]):
							lying.append("%s claims '%s' with no %s payload" % [sk_id, rule[2], rule[1]])
				sk_f = sk_dir.get_next()
	# --- Teleport is Bender-exclusive (class identity, like healer-res) ---
	# The owner's rule: only the Bender family teleports, the way only a
	# healer resurrects. A teleport payload on any other class is a broken
	# promise of class identity, so refuse it by name. required_role = 5 is
	# CharacterClass.Role.BENDER (Seer/Temporalist/Overclocker).
	var bad_tp: Array = []
	var tp_root := DirAccess.open("res://data/skills")
	if tp_root != null:
		tp_root.list_dir_begin()
		var tp_sub := tp_root.get_next()
		while tp_sub != "":
			var tp_dir_name := tp_sub
			tp_sub = tp_root.get_next()
			if tp_dir_name == "" or tp_dir_name.begins_with("."):
				continue
			var tp_dir := DirAccess.open("res://data/skills/%s" % tp_dir_name)
			if tp_dir == null:
				continue
			tp_dir.list_dir_begin()
			var tp_f := tp_dir.get_next()
			while tp_f != "":
				if tp_f.ends_with(".tres"):
					var tp_txt := FileAccess.get_file_as_string("res://data/skills/%s/%s" % [tp_dir_name, tp_f])
					if tp_txt.contains('"type": "teleport"') or tp_txt.contains('"type":"teleport"'):
						var tp_id := ""
						var tp_role := false
						for line in tp_txt.split("\n"):
							var lt := line.strip_edges()
							if lt.begins_with("id = \"") and tp_id == "":
								tp_id = lt.trim_prefix("id = \"").trim_suffix("\"")
							elif lt == "required_role = 5":
								tp_role = true
						if not tp_role:
							bad_tp.append(tp_id)
				tp_f = tp_dir.get_next()
	if bad_tp.is_empty():
		_ok("Skills: every teleport is Bender-exclusive")
	else:
		_fail("Teleport skills outside the Bender role: %s" % ", ".join(bad_tp))

	# --- A description that promises a multi-ally mend must band ---
	# The scope bands turn a heal into a friendly AoE from the epic tier up,
	# but only for a skill that opts in (scope_bands = true). A heal whose text
	# promises "every nearby ally" without the opt-in is the same lie as a
	# teleport with no role gate: the tooltip outruns the payload.
	var band_claims := ["every nearby ally", "every ally", "all nearby allies", "all allies"]
	var bad_band: Array = []
	var band_root := DirAccess.open("res://data/skills")
	if band_root != null:
		band_root.list_dir_begin()
		var band_sub := band_root.get_next()
		while band_sub != "":
			var band_dir_name := band_sub
			band_sub = band_root.get_next()
			if band_dir_name == "" or band_dir_name.begins_with("."):
				continue
			var band_dir := DirAccess.open("res://data/skills/%s" % band_dir_name)
			if band_dir == null:
				continue
			band_dir.list_dir_begin()
			var band_f := band_dir.get_next()
			while band_f != "":
				if band_f.ends_with(".tres"):
					var band_txt := FileAccess.get_file_as_string("res://data/skills/%s/%s" % [band_dir_name, band_f])
					var band_id := ""
					var band_desc := ""
					var band_opts := false
					var band_heals := false
					for line in band_txt.split("\n"):
						var bl := line.strip_edges()
						if bl.begins_with("id = \"") and band_id == "":
							band_id = bl.trim_prefix("id = \"").trim_suffix("\"")
						elif bl.begins_with("description = \""):
							band_desc = bl.to_lower()
						elif bl == "scope_bands = true":
							band_opts = true
						elif bl.begins_with("aoe_radius = "):
							# An authored ring is inherently an AoE heal.
							var av := bl.trim_prefix("aoe_radius = ").to_float()
							if av > 0.0:
								band_opts = true
						elif bl.begins_with("effects = ") and bl.to_lower().contains("\"type\": \"heal\""):
							band_heals = true
					if band_heals:
						for phrase in band_claims:
							if band_desc.contains(phrase) and not band_opts:
								bad_band.append("%s ('%s')" % [band_id, phrase])
								break
				band_f = band_dir.get_next()
	if bad_band.is_empty():
		_ok("Skills: every multi-ally mend claim opts into scope bands")
	else:
		_fail("Heals promising a multi-ally mend without scope_bands = true: %s" % ", ".join(bad_band))

	# --- A description that promises a ring of control, or a party-wide
	# guard, must author a ring or opt into the matching band. Same law as
	# the mend claim above, once for each of the tank's verbs.
	var ctrl_claims := ["nearby enemies", "nearby foes", "all nearby enemies",
		"all nearby foes", "every nearby foe", "every nearby enemy",
		"enemies within range", "enemies in a cone", "all enemies inside",
		"nearby systems", "every mind nearby", "every foe nearby"]
	var guard_claims := ["nearby allies", "all nearby allies", "all allies",
		"every nearby ally", "all party members", "nearby party members"]
	var bad_ctrl: Array = []
	var bad_guard: Array = []
	var cg_root := DirAccess.open("res://data/skills")
	if cg_root != null:
		cg_root.list_dir_begin()
		var cg_sub := cg_root.get_next()
		while cg_sub != "":
			var cg_dir_name := cg_sub
			cg_sub = cg_root.get_next()
			if cg_dir_name == "" or cg_dir_name.begins_with("."):
				continue
			var cg_dir := DirAccess.open("res://data/skills/%s" % cg_dir_name)
			if cg_dir == null:
				continue
			cg_dir.list_dir_begin()
			var cg_f := cg_dir.get_next()
			while cg_f != "":
				if cg_f.ends_with(".tres"):
					var cg_txt := FileAccess.get_file_as_string("res://data/skills/%s/%s" % [cg_dir_name, cg_f])
					var cg_id := ""
					var cg_desc := ""
					var cg_aoe := 0.0
					var cg_scope := false
					var cg_guard := false
					for line in cg_txt.split("\n"):
						var cl := line.strip_edges()
						if cl.begins_with("id = \"") and cg_id == "":
							cg_id = cl.trim_prefix("id = \"").trim_suffix("\"")
						elif cl.begins_with("description = \""):
							cg_desc = cl.to_lower()
						elif cl.begins_with("aoe_radius = "):
							cg_aoe = cl.trim_prefix("aoe_radius = ").to_float()
						elif cl == "scope_bands = true":
							cg_scope = true
						elif cl == "guard_band = true":
							cg_guard = true
					var cg_fx := _bracket_block(cg_txt, "effects").to_lower()
					var cg_has_ctrl := false
					for k in ["stun", "root", "slow", "taunt", "silence", "fear", "knockback"]:
						if cg_fx.contains(k):
							cg_has_ctrl = true
							break
					var cg_has_guard := cg_fx.contains("\"type\": \"shield\"") or cg_fx.contains("\"type\": \"buff\"")
					if cg_has_ctrl and not (cg_scope or cg_aoe > 0.0):
						for phrase in ctrl_claims:
							if cg_desc.contains(phrase):
								bad_ctrl.append("%s ('%s')" % [cg_id, phrase])
								break
					if cg_has_guard and not (cg_guard or cg_aoe > 0.0):
						for phrase in guard_claims:
							if cg_desc.contains(phrase):
								bad_guard.append("%s ('%s')" % [cg_id, phrase])
								break
				cg_f = cg_dir.get_next()
	if bad_ctrl.is_empty():
		_ok("Skills: every multi-enemy control claim authors a ring or bands")
	else:
		_fail("Control promising a ring without aoe_radius/scope_bands: %s" % ", ".join(bad_ctrl))
	if bad_guard.is_empty():
		_ok("Skills: every multi-ally guard claim authors a ring or bands")
	else:
		_fail("Guards promising a party-wide shield without aoe_radius/guard_band: %s" % ", ".join(bad_guard))

	# --- The starter law: every family's FIRST skill carries its verb ---
	# Healer gets the mend, bender the blink, tank the grab (control). The
	# damage lanes (DD/MAGE/ROGUE) carry damage. The same law for every
	# family, read off the class `role`, so a new class cannot ship with a
	# starter that ignores its lane.
	var role_verb := {
		1: "control",  # TANK
		2: "damage",   # DD
		3: "damage",   # MAGE
		4: "damage",   # ROGUE
		5: "teleport", # BENDER
		6: "heal",     # HEALER
	}
	var bad_starter: Array = []
	var starters_checked := 0
	var cls_root := DirAccess.open("res://data/classes")
	if cls_root != null:
		cls_root.list_dir_begin()
		var cf := cls_root.get_next()
		while cf != "":
			if cf.ends_with(".tres") and not cf.begins_with("gm_"):
				var ctxt := FileAccess.get_file_as_string("res://data/classes/%s" % cf)
				var cid := ""
				var c_role := -1
				var first_skill := ""
				for line in ctxt.split("\n"):
					var ct := line.strip_edges()
					if ct.begins_with("id = \"") and cid == "":
						cid = ct.trim_prefix("id = \"").trim_suffix("\"")
					elif ct.begins_with("role = ") and c_role < 0:
						c_role = ct.trim_prefix("role = ").to_int()
					elif ct.begins_with("starting_skills = [") and first_skill == "":
						var m := _skill_ref_regex().search(ct)
						if m != null:
							first_skill = m.get_string(1)
				if cid == "" or c_role < 0 or first_skill == "":
					cf = cls_root.get_next()
					continue
				var want := str(role_verb.get(c_role, ""))
				if want == "":
					cf = cls_root.get_next()
					continue
				starters_checked += 1
				var stxt := _skill_text_by_id(first_skill)
				if stxt == "" or not _skill_has_verb(stxt, want):
					bad_starter.append("%s (%s wants %s)" % [cid, first_skill, want])
			cf = cls_root.get_next()
	if bad_starter.is_empty():
		_ok("Skills: every family's first skill carries its identity verb (%d checked)" % starters_checked)
	else:
		_fail("First skills missing their family verb: %s" % ", ".join(bad_starter))

	_finish()
