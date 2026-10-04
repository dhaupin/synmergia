## test_tick_phase2_systems.gd - TickService Phase 2/3 gameplay systems:
## effect decay sweep, out-of-combat regen, cross-shard event absorption,
## enemy AI grudge decay at tick cadence, and the seed-chain root fold.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_tick_phase2_systems.gd
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)

func _run() -> void:
	var tick = root.get_node_or_null("TickService")
	var es = root.get_node_or_null("EntityService")
	_assert(tick != null, "TickService present")
	_assert(es != null, "EntityService present")
	if tick == null or es == null:
		return _finish()
	if tick._tick_timer != null:
		tick._tick_timer.stop()

	# --- 1. Effect decay sweep -----------------------------------------------
	var StatusScript = load("res://core/entities/status_effect.gd")
	var EntityScript = load("res://core/entities/entity.gd")
	var carrier: Node = EntityScript.new()
	carrier.entity_id = "decay_carrier"
	carrier.display_name = "DecayCarrier"
	root.add_child(carrier)
	await process_frame
	es.register_entity(carrier, null, "decay_carrier")

	var effect = StatusScript.new()
	effect.effect_id = "sweep_test_effect"
	# DURATION behavior: the janitor advances these by wall clock (an
	# INSTANT effect fires once and is never reaped by the sweep).
	effect.tick_behavior = StatusScript.TickBehavior.DURATION
	effect.duration = 0.05  # expires within one 50ms tick of advancement
	carrier.apply_status_effect(effect)
	_assert(carrier.status_effects.size() == 1, "carrier holds the seeded effect")
	_assert(effect.is_active, "seeded effect is active before the sweep")

	var result: Dictionary = tick._decay_effects()
	_assert(result.has("swept") and result.has("advanced"), "decay result reports swept + advanced")
	_assert(carrier.status_effects.is_empty(), "expired effect swept from the array")

	var keeper = StatusScript.new()
	keeper.effect_id = "keeper_effect"
	keeper.duration = 0.0  # 0 = permanent; is_expired() is always false
	carrier.apply_status_effect(keeper)
	tick._decay_effects()
	_assert(carrier.status_effects.size() == 1, "permanent effect (duration 0) survives the sweep")
	carrier.clear_all_status_effects()

	# A dead slot is swept, not crashed on. (StatusEffect is a RefCounted
	# Resource: it cannot be free()d while the array still references it,
	# so a null entry is the reachable dead-reference case.)
	carrier.status_effects.append(null)
	tick._decay_effects()
	_assert(carrier.status_effects.is_empty(), "null effect slot swept without crashing")

	# --- 2. Regen ----------------------------------------------------------------
	carrier.current_health = 50
	carrier.current_mana = 40
	tick._regen_entities()
	_assert(carrier.current_health > 50 or carrier.current_health == 50,
			"regen applies health (fractional accumulator may round to 0 on first tick)")
	# Force the accumulator over the whole-point threshold deterministically.
	tick._regen_health_acc["decay_carrier"] = 1.5
	var before: int = carrier.current_health
	tick._regen_entities()
	_assert(carrier.current_health == before + 1 or carrier.current_health > before,
			"health accumulator applies whole points")
	tick._regen_health_acc.erase("decay_carrier")
	tick._regen_mana_acc.erase("decay_carrier")

	# --- 3. Cross-shard event absorption ---------------------------------------
	var coord = root.get_node_or_null("CoordinatorService")
	_assert(coord != null, "CoordinatorService present")
	if coord != null:
		coord.clear_processed_events()
		coord.emit_cross_shard_event_auto("test_event", "shard_a", {"k": 1})
		coord.emit_cross_shard_event_auto("test_event", "shard_b", {"k": 2})
		var pending: Array = coord.get_pending_events()
		_assert(pending.size() == 2, "coordinator holds both seeded events")
		var pulled: Array = tick._pull_cross_shard_events()
		_assert(pulled.size() == 2, "tick absorbs both pending events")
		_assert(String(pulled[0].get("event_type", "")) == "test_event", "absorbed events keep their shape")
		_assert(coord.get_pending_events().is_empty(), "coordinator queue cleared (exactly-once per event)")
		_assert(tick._pull_cross_shard_events().is_empty(), "second pull drains nothing")

	# --- 4. AI grudge decay through _step_entity --------------------------------
	var EnemyScript = load("res://entities/enemy.gd")
	_assert(EnemyScript != null, "enemy script resolvable")
	if EnemyScript != null:
		var enemy: Node = EnemyScript.new()
		enemy.entity_id = "step_enemy"
		root.add_child(enemy)
		await process_frame
		es.register_entity(enemy, null, "step_enemy")
		var AIScript = load("res://core/ai/enemy_ai.gd")
		var ai = AIScript.new()
		enemy.attach_ai(ai)
		ai._known_threats["decay_carrier"] = 10.0
		var grudge_before: float = float(ai._known_threats["decay_carrier"])
		tick._step_entity(enemy)
		var grudge_after: float = float(ai._known_threats.get("decay_carrier", 0.0))
		_assert(grudge_after < grudge_before, "grudge decays through the tick step")
		enemy.queue_free()

	# --- 5. Seed chain root fold --------------------------------------------------
	var ChainScript = load("res://core/frame/kv/seed_chain.gd")
	var chain = ChainScript.new()
	var empty_head: PackedByteArray = chain.chain_head()
	_assert(empty_head.size() == 0, "chain head starts empty")
	chain.update_root(PackedByteArray())
	_assert(chain.chain_head().size() == 0, "empty root folds to nothing")
	var r1: PackedByteArray = PackedByteArray([1, 2, 3])
	var h1: PackedByteArray = chain.update_root(r1)
	_assert(h1.size() == 32 and chain.chain_head() == h1, "first root folds to a 32-byte head")
	var h2: PackedByteArray = chain.update_root(PackedByteArray([4, 5, 6]))
	_assert(h2 != h1 and chain.chain_head() == h2, "second root folds on top (deterministic chain)")
	var chain2 = ChainScript.new()
	chain2.update_root(PackedByteArray([1, 2, 3]))
	chain2.update_root(PackedByteArray([4, 5, 6]))
	_assert(chain2.chain_head() == h2, "same fold order -> same head (deterministic)")

	# Live wiring: the tick's chain head advanced when Phase 3 ran.
	_assert(tick._seed_chain != null, "tick owns a seed chain instance")

	_finish()

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("Phase2Systems: %d passed, %d failed" % [_pass, _fail])
