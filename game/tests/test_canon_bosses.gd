## Smoke test: canon world bosses (Clockwork Saint + Mossbound Herald).
## Encodes story-PRD canon as mechanics: the Herald is NEUTRAL
## (passive, near-zero aggro -- zero magenta in its art canon), the
## Saint is half-corrupted and aggressive (one magenta eye). Also
## verifies both EnemyData templates resolve, both WorldBossData
## schedules are well-formed, and their zone ids exist.
## Run: cd game && godot --headless --path . --script res://tests/test_canon_bosses.gd
extends SceneTree

func _init() -> void:
	var ok := true
	# 1. Both EnemyData templates load and resolve
	for id in ["clockwork_saint", "mossbound_herald"]:
		var e = load("res://data/enemies/enemy_%s.tres" % id)
		if e == null or e.id != id:
			push_error("FAIL: template %s missing/wrong id" % id)
			ok = false
			continue
		if not e.is_boss or e.enemy_type != 4:
			push_error("FAIL: %s not WORLD_BOSS typed" % id)
			ok = false
		print("PASS: template %s (lvl %d, hp %d)" % [e.id, e.level, e.health])
	# 2. Herald neutrality law: passive, near-zero aggro
	var h = load("res://data/enemies/enemy_mossbound_herald.tres")
	if h.is_aggressive or not h.is_passive or h.aggro_range > 2.0:
		push_error("FAIL: Herald must be passive (neutral canon)")
		ok = false
	else:
		print("PASS: Herald is passive, aggro_range %.1f" % h.aggro_range)
	# 3. Saint keeps the magenta-eye law: aggressive half-corrupted
	var s = load("res://data/enemies/enemy_clockwork_saint.tres")
	if not s.is_aggressive:
		push_error("FAIL: Saint must be aggressive (half-corrupted)")
		ok = false
	else:
		print("PASS: Saint is aggressive")
	# 4. Schedules load with template ids resolving
	for id in ["clockwork_saint", "mossbound_herald"]:
		var wb = load("res://data/world_bosses/world_boss_%s.tres" % id)
		if wb == null or wb.boss_template_id != id or wb.zone_id == "":
			push_error("FAIL: schedule %s malformed" % id)
			ok = false
		elif str(wb.display_name).is_empty():
			# An empty display_name renders blank in the boss bar and the
			# spawn announce (the schedule aliases the template's name).
			push_error("FAIL: schedule %s has no display_name" % id)
			ok = false
		else:
			print("PASS: schedule %s -> %s (%s) in %s" % [wb.id, wb.boss_template_id, wb.display_name, wb.zone_id])
	# 5. Zone ids resolve to real zones
	for z in ["zone_dungeon_forest_depths", "zone_starter_plains"]:
		var zone = load("res://data/zones/%s.tres" % z)
		if zone == null:
			push_error("FAIL: zone %s missing" % z)
			ok = false
		else:
			print("PASS: zone %s exists" % z)
	print("test_canon_bosses: %s" % ("ALL PASS" if ok else "FAILURES"))
	quit(0 if ok else 1)
