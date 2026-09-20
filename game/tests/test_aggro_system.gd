## Aggro system integration tests: threat table, taunts, heal threat,
## target switching, grudge decay, and memory persistence.
extends SceneTree

const AggroComponent = preload("res://core/components/aggro_component.gd")
const MemoryTreeScript = preload("res://core/frame/kv/memory_tree.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	_test_component_compiles()
	_test_damage_threat_and_switching()
	_test_taunt_locks_target()
	_test_taunt_expiry()
	_test_taunt_resist()
	_test_aggro_dump_reduce()
	_test_aggro_dump_scale()
	_test_heal_threat()
	_test_threat_modifiers()
	_test_transfer_threat_fixed()
	_test_decay_removes_stale()
	_test_grudge_decay_on_return()
	_test_enemy_has_component_on_ready()
	_test_ai_persists_memory()
	print("AggroSystem tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _mk_entity(id: String):
	var s = load("res://core/entities/entity.gd")
	var e = s.new()
	e.entity_id = id
	e.display_name = id
	return e


func _test_component_compiles() -> void:
	var ac = AggroComponent.new()
	_assert(ac != null, "AggroComponent instantiates")
	ac.free()


func _test_damage_threat_and_switching() -> void:
	var ac = AggroComponent.new()
	var a = _mk_entity("ta"); var b = _mk_entity("tb")
	ac.add_damage_threat(a, 100)
	_assert(ac.get_highest_threat_target() == a, "first damager leads threat")
	ac.add_damage_threat(b, 150)
	_assert(ac.get_highest_threat_target() == b, "higher damager takes over target (switching)")
	_assert(ac.get_threat(a) == 100, "original threat preserved")
	ac.add_threat(a, 100)
	_assert(ac.get_highest_threat_target() == a, "overtaking threat switches target back")
	a.free(); b.free(); ac.free()


func _test_taunt_locks_target() -> void:
	var ac = AggroComponent.new()
	var a = _mk_entity("tk_a"); var tank = _mk_entity("tk_tank"); var c = _mk_entity("tk_c")
	ac.add_threat(a, 500)
	ac._enter_combat(a)
	var ok: bool = ac.taunt(tank, 60000)
	_assert(ok, "taunt succeeds on non-resistant target")
	_assert(ac.get_highest_threat_target() == tank, "taunt places tank on top")
	_assert(ac.is_taunted(), "component reports taunted state")
	ac.add_threat(c, 99999)
	_assert(ac._current_target == tank, "taunt force-locks target despite massive damage")
	a.free(); tank.free(); c.free(); ac.free()


func _test_taunt_expiry() -> void:
	var ac = AggroComponent.new()
	var a = _mk_entity("te_a"); var tank = _mk_entity("te_tank")
	ac.add_threat(a, 500)
	ac.taunt(tank, 30)  # 30ms
	# Drive _process manually (the component is not in the tree here).
	for i in range(6):
		ac._process(0.05)  # 300ms total > 30ms taunt
	_assert(not ac.is_taunted(), "taunt expires after duration")
	# Sticky threat: the tank legitimately stays on top after expiry
	# (taunt placed him above the prior leader; no snap-back).
	_assert(ac.get_highest_threat_target() == tank, "tank keeps target after expiry via sticky threat")
	# But damage can still take the target back:
	ac.add_threat(a, 5000)
	_assert(ac.get_highest_threat_target() == a, "out-threatening the tank retakes target after expiry")
	a.free(); tank.free(); ac.free()


func _test_taunt_resist() -> void:
	var ac = AggroComponent.new()
	# taunt_resist is exported; set after instantiation
	ac.set("taunt_resist", true)
	var tank = _mk_entity("tr_tank")
	var ok: bool = ac.taunt(tank, 60000)
	_assert(ok == false, "taunt_resist boss ignores taunt")
	_assert(not ac.is_taunted(), "no taunt lock on resistant target")
	tank.free(); ac.free()


func _test_aggro_dump_reduce() -> void:
	var ac = AggroComponent.new()
	var a = _mk_entity("rd_a")
	ac.add_threat(a, 1000)
	ac.reduce_threat(a, 400)
	_assert(ac.get_threat(a) == 600, "reduce_threat lowers threat")
	ac.reduce_threat(a, 99999)
	_assert(ac.get_threat(a) == 0, "reduce_threat floors at 0")
	a.free(); ac.free()


func _test_aggro_dump_scale() -> void:
	var ac = AggroComponent.new()
	var a = _mk_entity("sc_a")
	ac.add_threat(a, 1000)
	ac.scale_threat(a, 0.5)
	_assert(ac.get_threat(a) == 500, "scale_threat halves threat (feign death)")
	ac.scale_threat(a, 0.0)
	_assert(ac.get_threat(a) == 0, "scale_threat 0 dumps all threat")
	a.free(); ac.free()


func _test_heal_threat() -> void:
	var ac = AggroComponent.new()
	ac.heal_threat_factor = 0.5
	var healer = _mk_entity("ht_heal")
	ac.record_heal_threat(healer, 200)
	_assert(ac.get_threat(healer) == 100, "heal of 200 generates 100 threat at 0.5x")
	ac.heal_threat_factor = 0.0
	ac.record_heal_threat(healer, 200)
	_assert(ac.get_threat(healer) == 100, "0.0 factor generates no extra threat")
	healer.free(); ac.free()


func _test_threat_modifiers() -> void:
	var ac = AggroComponent.new()
	ac.threat_modifiers = {"physical": 0.5}
	var a = _mk_entity("tm_a")
	ac.add_damage_threat(a, 100, "physical")
	_assert(ac.get_threat(a) == 50, "physical damage threat halved by modifier")
	ac.add_damage_threat(a, 100, "magic")
	_assert(ac.get_threat(a) == 150, "unmodified damage type uses full threat")
	a.free(); ac.free()


func _test_transfer_threat_fixed() -> void:
	var ac = AggroComponent.new()
	var a = _mk_entity("tt_a"); var receiver = _mk_entity("tt_recv")
	ac.add_threat(a, 300)
	ac.transfer_threat_to(receiver)  # must not crash; receiver has no aggro_component property
	_assert(ac.get_threat(a) == 300, "transfer leaves source table intact (receiver lacks component)")
	a.free(); receiver.free(); ac.free()


func _test_decay_removes_stale() -> void:
	var ac = AggroComponent.new()
	ac.threat_decay_rate = 1000.0
	var a = _mk_entity("dec_a"); var b = _mk_entity("dec_b")
	ac.add_threat(a, 500)
	ac.add_threat(b, 100)
	ac._decay_threat(0.2)  # 200 decay
	_assert(ac.get_threat(a) == 300, "threat decays over time")
	_assert(ac.get_threat(b) == 0, "fully decayed threat floors to 0")
	ac._decay_threat(1.0)  # removes zeroed entries
	_assert(not ac.get_all_threat_targets().has(b), "zero-threat target removed from table (no mid-iteration erase)")
	a.free(); b.free(); ac.free()


func _test_grudge_decay_on_return() -> void:
	var ai_s = load("res://core/ai/enemy_ai.gd")
	var ai = ai_s.new()
	ai._memory_agent_path = "memory/enemies/grudge_decay_test"
	ai.remember("hit_gp1", {"player_id": "gp1", "action": "attacked", "time": 1000.0}, 1.0)
	ai._decay_grudges()
	var tree = ai._get_memory_tree()
	var mem: Dictionary = tree.get_memory("memory/enemies/grudge_decay_test/events/hit_gp1")
	_assert(absf(float(mem.get("weight")) - 0.5) < 0.001, "grudge weight halves after leash return")
	_assert(float(ai._known_threats.get("gp1", 0.0)) == 0.5, "known_threats reflect decayed weight")
	# Decay below threshold -> forgotten
	ai._decay_grudges()
	ai._decay_grudges()
	_assert(not ai._known_threats.has("gp1"), "grudge forgotten after repeated decay below threshold")
	ai.free()


func _test_enemy_has_component_on_ready() -> void:
	var enemy_s = load("res://entities/enemy.gd")
	var e = enemy_s.new()
	# _ready is called on tree entry; call manually for this probe
	e._ready()
	_assert(e.aggro_component != null, "Enemy gains AggroComponent in _ready")
	_assert(e.get_child_count() > 0, "AggroComponent attached as child")
	e.free()


func _test_ai_persists_memory() -> void:
	var ai_s = load("res://core/ai/enemy_ai.gd")
	var ai = ai_s.new()
	ai._memory_agent_path = "memory/enemies/persist_probe_ai"
	ai.remember("hit_pp1", {"player_id": "pp1", "action": "attacked", "time": 555.0}, 0.9)
	ai._persist_memory()
	var store = ai._kv_store()
	var key: String = ai.MEMORY_KV_KEY % ai._memory_agent_path
	_assert(store.has_key(key), "memory persisted to durable KV store")
	# New AI instance restores from the store
	var ai2 = ai_s.new()
	ai2._memory_agent_path = "memory/enemies/persist_probe_ai"
	ai2._restore_memory()
	_assert(float(ai2._known_threats.get("pp1", 0.0)) == 0.9, "restored AI knows remembered attacker")
	# Cleanup persisted key
	store.erase(key)
	ai.free(); ai2.free()


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % msg)
