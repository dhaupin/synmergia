## Lane L load probe: every equipment .tres loads, its id resolves through
## DataService, no field is a phantom (absent from the Item schema), every
## playable class has signature weapon + armor, the missing enum values are
## covered, and the armory offering can actually sell class-locked gear.
##
## Run: cd game && godot --headless --path . --script res://dev_temp/probes/lane_l_load.gd
extends SceneTree

var _checks: int = 0
var _fails: int = 0

func _check(label: String, cond: bool, extra: String = "") -> void:
	_checks += 1
	if cond:
		print("  PASS " + label + (" " + extra if extra != "" else ""))
	else:
		_fails += 1
		print("  FAIL " + label + (" " + extra if extra != "" else ""))

func _schema_fields() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://core/schemas/item.gd", FileAccess.READ)
	var in_enum := false
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("enum "):
			in_enum = true
			continue
		if in_enum:
			if line.begins_with("}"):
				in_enum = false
			continue
		var m := line.strip_edges()
		if m.begins_with("@export var ") or m.begins_with("var "):
			var nm := m.replace("@export var ", "").replace("var ", "").split(":")[0].split("=")[0].strip_edges()
			out[nm] = true
	return out

func _file_fields(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	var in_dict := false
	while not f.eof_reached():
		var line := f.get_line()
		var t := line.strip_edges()
		if in_dict:
			if t.begins_with("}"):
				in_dict = false
			continue
		if t.ends_with("= {"):
			in_dict = true
			continue
		var m := t.split(" = ")
		if m.size() >= 2:
			out.append(m[0].strip_edges())
	return out

func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)
	if ds == null:
		quit(1)
		return

	var schema := _schema_fields()
	var known_meta := {"script": true, "resource_local_to_scene": true,
		"resource_name": true, "resource_path": true}
	var phantom: Array = []
	var new_ids: Array = []
	var fams := ["weapons", "armors", "accessories"]
	for fam in fams:
		var dir := DirAccess.open("res://data/" + fam)
		_check("data/" + fam + " exists", dir != null)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".tres"):
				var path := "res://data/%s/%s" % [fam, fn]
				var res = load(path)
				var expect_id: String = fn.trim_suffix(".tres")
				if res == null:
					_check("load " + fam + "/" + fn, false, "(null)")
				else:
					var ok_id: bool = str(res.get("id")) == expect_id
					_check("load+id " + fam + "/" + fn, ok_id,
						"" if ok_id else "(id=%s)" % str(res.get("id")))
					var via = ds.get_item(expect_id)
					_check("resolve " + expect_id, via != null)
					new_ids.append(expect_id)
				for field in _file_fields(path):
					if not schema.has(field) and not known_meta.has(field):
						phantom.append("%s: %s" % [fn, field])
			fn = dir.get_next()

	_check("no phantom fields in equipment .tres", phantom.is_empty(), str(phantom))

	# Class coverage.
	var classes: Array = []
	var cdir := DirAccess.open("res://data/classes")
	cdir.list_dir_begin()
	var cf := cdir.get_next()
	while cf != "":
		if cf.ends_with(".tres") and not cf.begins_with("class_gm_"):
			var cd = load("res://data/classes/" + cf)
			if cd != null:
				classes.append(str(cd.get("id")))
		cf = cdir.get_next()
	var w_by_class := {}
	var a_by_class := {}
	for iid in new_ids:
		var it = ds.get_item(iid)
		if it == null:
			continue
		var rc: String = str(it.get("required_class"))
		if rc == "":
			continue
		if it.item_category == 0:
			w_by_class[rc] = int(w_by_class.get(rc, 0)) + 1
		elif it.item_category == 1:
			a_by_class[rc] = int(a_by_class.get(rc, 0)) + 1
	var miss_w: Array = []
	var miss_a: Array = []
	for c in classes:
		if int(w_by_class.get(c, 0)) < 1:
			miss_w.append(c)
		if int(a_by_class.get(c, 0)) < 1:
			miss_a.append(c)
	_check("every playable class has a signature weapon (%d classes)" % classes.size(), miss_w.is_empty(), str(miss_w))
	_check("every playable class has a signature armor (%d classes)" % classes.size(), miss_a.is_empty(), str(miss_a))

	# Enum coverage.
	var wt := {}
	var at := {}
	var act := {}
	for iid in new_ids:
		var it = ds.get_item(iid)
		if it == null:
			continue
		if it.item_category == 0:
			wt[int(it.get("weapon_type"))] = true
		elif it.item_category == 1:
			at[int(it.get("armor_type"))] = true
		elif it.item_category == 2:
			act[int(it.get("accessory_type"))] = true
	var miss_wt: Array = []
	for v in range(1, 11):
		if not wt.has(v):
			miss_wt.append(v)
	var miss_at: Array = []
	for v in range(1, 5):
		if not at.has(v):
			miss_at.append(v)
	var miss_act: Array = []
	for v in range(1, 7):
		if not act.has(v):
			miss_act.append(v)
	_check("every WeaponType 1..10 has an item", miss_wt.is_empty(), str(miss_wt))
	_check("every ArmorType 1..4 has an item", miss_at.is_empty(), str(miss_at))
	_check("every AccessoryType 1..6 has an item", miss_act.is_empty(), str(miss_act))

	# Armory sells class-locked gear.
	var offering = load("res://data/npc_offerings/armory.tres")
	_check("armory offering loads", offering != null)
	if offering != null:
		var vs = load("res://core/services/vendor_service.gd").singleton()
		if vs != null and vs.has_method("_resolve_catalog_items"):
			var catalog: Array = vs._resolve_catalog_items(offering, null)
			_check("armory catalog is non-empty", catalog.size() > 0, "(%d)" % catalog.size())
			var locked: int = 0
			for it in catalog:
				if it != null and str(it.get("required_class")) != "":
					locked += 1
			_check("armory catalog sells class-locked gear", locked > 0, "(%d)" % locked)

	print("--- LANE-L-PROBE: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)

func _init() -> void:
	call_deferred("_run")
