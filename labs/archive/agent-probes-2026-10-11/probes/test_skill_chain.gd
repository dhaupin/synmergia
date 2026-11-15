## Probe: schema -> runtime skill converter + player cast surface.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var ok := true

	var schema_script = load("res://core/schemas/skill.gd")
	var schema = schema_script.new()
	schema.id = "human_strike"
	schema.display_name = "Strike"
	schema.mana_cost = 8
	schema.cooldown = 3.0
	var eff: Array[Dictionary] = [{"type": "damage", "value": 18}]
	schema.effects = eff

	var runtime_script = load("res://core/combat/skill.gd")
	var skill = runtime_script.from_schema(schema)
	if skill == null or skill.skill_id != "human_strike":
		push_error("FAIL: from_schema returned bad skill")
		ok = false
	elif skill.damage != 18:
		push_error("FAIL: effect value not extracted into skill.damage (got %s)" % str(skill.damage))
		ok = false
	else:
		print("PASS: from_schema -> id=%s damage=%d cooldown=%.1f mana=%d" % [skill.skill_id, skill.damage, skill.cooldown, skill.mana_cost])

	var pc = load("res://entities/player/player_controller.gd").new()
	if not ("current_mana" in pc and "max_mana" in pc):
		push_error("FAIL: PlayerController missing mana fields")
		ok = false
	else:
		print("PASS: player mana pool present (max=%d)" % pc.max_mana)
	pc.free()

	quit(0 if ok else 1)
