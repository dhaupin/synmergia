## test_stamina.gd - stamina is one shared resource with one regen owner.
##
##   1. PlayerBase carries max/current stamina from endurance and exposes
##      use/restore (the surface Entity already had).
##   2. TickService applies the authored rest/combat stamina rates and the
##      flat stamina_regen stat through the same accumulator as HP/MP.
##   3. A status-effect stamina_regen payload reaches the stat block.
##
## Run headless:
##   godot --headless --path game --script res://tests/test_stamina.gd
## Exit 0 = all pass.
extends SceneTree

const PlayerBaseScript = preload("res://entities/player/player_base.gd")
const EntityScript = preload("res://core/entities/entity.gd")
const EnemyDataScript = preload("res://core/schemas/enemy_data.gd")
const StatusEffectDataScript = preload("res://core/schemas/status_effect_data.gd")
const Factory = preload("res://core/combat/status_effect_factory.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- STAMINA: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	var player = PlayerBaseScript.new()
	player.name = "StaminaProbePlayer"
	root.add_child(player)
	await process_frame

	# --- 1. The player pool ----------------------------------------------
	_assert(_approx(player.max_stamina, 150.0), "endurance 10 gives a 150 stamina pool")
	_assert(_approx(player.current_stamina, player.max_stamina), "the player starts full")
	_assert(player.use_stamina(30.0), "use_stamina spends a real cost")
	_assert(_approx(player.current_stamina, 120.0), "use_stamina subtracts the cost")
	_assert(not player.use_stamina(999.0), "use_stamina refuses an unaffordable cost")
	player.restore_stamina(999.0)
	_assert(_approx(player.current_stamina, player.max_stamina), "restore_stamina clamps to max")

	player.set_stat("endurance", 20)
	_assert(_approx(player.max_stamina, 200.0), "endurance raises the stamina ceiling")
	_assert(_approx(player.current_stamina, 150.0), "raising the ceiling preserves the current pool")

	# --- 2. TickService is the regen owner --------------------------------
	var ts = root.get_node_or_null("TickService")
	var es = root.get_node_or_null("EntityService")
	_assert(ts != null, "TickService autoload is available")
	_assert(es != null, "EntityService autoload is available")
	if ts != null:
		var rest_rates: Dictionary = ts._regen_rates(false)
		var combat_rates: Dictionary = ts._regen_rates(true)
		_assert(_approx(float(rest_rates.get("stamina_pct", 0.0)), 0.02),
			"rest stamina rate is 2% of max per second")
		_assert(_approx(float(combat_rates.get("stamina_pct", 0.0)), 0.01),
			"combat stamina rate is 1% of max per second")
	if ts != null and es != null:
		player.entity_id = "test_stamina_body"
		es.register_entity(player)
		player.current_stamina = 0.0
		player.stats["stamina_regen"] = 5.0
		var prior_interval: float = float(ts._tick_interval)
		ts._tick_interval = 1000.0
		ts._regen_stamina_acc.clear()
		ts._regen_entities()
		ts._tick_interval = prior_interval
		# 2% of 200 = 4 from the record, plus 5 flat from the stat.
		_assert(_approx(player.current_stamina, 9.0),
			"one second of regen applies baseline + flat stamina")
		es.unregister_entity(player)

	# --- 3. Regen reaches a status-effect payload -------------------------
	var data = StatusEffectDataScript.new()
	data.id = "test_stamina_regen"
	data.display_name = "Test Stamina Regen"
	data.duration = 10.0
	data.stamina_regen = 2.5
	var fx = Factory.from_data(data)
	_assert(fx != null and _approx(float(fx.stamina_regen_mod), 2.5),
		"a stamina_regen payload maps onto the status effect")
	var body = EntityScript.new()
	root.add_child(body)
	body.apply_status_effect(fx)
	_assert(_approx(float(body.stats.get("stamina_regen", 0.0)), 2.5),
		"the applied effect lands on the entity stat block")
	body.remove_status_effect(fx)
	_assert(_approx(float(body.stats.get("stamina_regen", 0.0)), 0.0),
		"removing the effect reverses the stat delta")

	# --- 4. Enemy templates seed the body pool ---------------------------
	var template = EnemyDataScript.new()
	template.id = "test_bear_stamina"
	template.stamina = 220
	var mob = EntityScript.new()
	root.add_child(mob)
	template.apply_stats_to(mob)
	_assert(_approx(mob.max_stamina, 220.0), "a template's stamina seeds the body ceiling")
	_assert(_approx(mob.current_stamina, 220.0), "a fresh spawn starts at full stamina")
	template.apply_stats_to(mob, 5)
	_assert(_approx(mob.max_stamina, 308.0), "a level-raised spawn scales the authored stamina")
	mob.queue_free()

	# --- 5. Mounts own a separate movement pool --------------------------
	var rides = root.get_node_or_null("RideService")
	var ds = root.get_node_or_null("DataService")
	_assert(rides != null, "RideService autoload is available")
	_assert(ds != null, "DataService autoload is available")
	if rides != null and ds != null:
		var mount = ds.get_mount("mount_meadow_pacer")
		_assert(mount != null and int(mount.stamina) > 0, "the mount data authors a stamina pool")
		var rider_id := "test_mount_stamina_rider"
		if not rides.owns_mount(rider_id, "mount_meadow_pacer"):
			_assert(rides.grant_mount(rider_id, "mount_meadow_pacer"), "the test mount grants")
		_assert(rides.summon(rider_id, "mount_meadow_pacer"), "the test mount summons")
		_assert(_approx(rides.get_mount_max_stamina(rider_id), float(mount.stamina)),
			"the mounted pool ceiling comes from MountData")
		_assert(_approx(rides.get_mount_stamina(rider_id), rides.get_mount_max_stamina(rider_id)),
			"a summoned mount arrives rested")
		_assert(rides.spend_mount_stamina(rider_id, 10.0), "a mounted sprint can spend the mount pool")
		_assert(_approx(rides.get_mount_stamina(rider_id), float(mount.stamina) - 10.0),
			"the spend lands on the mount pool, not the rider")
		rides.restore_mount_stamina(rider_id, 999.0)
		_assert(_approx(rides.get_mount_stamina(rider_id), float(mount.stamina)),
			"mount restore clamps to the authored ceiling")
		_assert(rides.dismiss(rider_id), "the test mount dismisses")
		_assert(_approx(rides.get_mount_stamina(rider_id), 0.0),
			"dismount clears the mount pool")
		rides.revoke_mount(rider_id, "mount_meadow_pacer")

	player.queue_free()
	body.queue_free()
