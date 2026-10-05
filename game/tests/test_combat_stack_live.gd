## test_combat_stack_live.gd - R28: the resurrected effect stack is live
## on the real attack path (CombatSystem -> skill appliers ->
## Entity/PlayerController status surfaces -> AuraComponent mirror ->
## EventHub signals), and CombatComponent gates player casts.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_combat_stack_live.gd
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
	var EntityScript = load("res://core/entities/entity.gd")
	var EnemyScript = load("res://entities/enemy.gd")
	var PlayerScript = load("res://entities/player/player_controller.gd")
	var SkillScript = load("res://core/combat/skill.gd")
	var StatusScript = load("res://core/entities/status_effect.gd")
	var hub = root.get_node_or_null("EventHub")
	var es = root.get_node_or_null("EntityService")
	_assert(hub != null, "EventHub present")
	_assert(EntityScript != null and SkillScript != null and StatusScript != null, "core scripts resolvable")

	# --- 1. Stack attach -------------------------------------------------------
	var carrier: Node = EntityScript.new()
	carrier.entity_id = "stack_carrier"
	root.add_child(carrier)
	await process_frame
	_assert(carrier.aura_component != null, "Entity gains an aura component (R28 attach)")
	_assert(carrier.combat_component == null, "plain Entity does not carry a combat component")

	var enemy: Node = EnemyScript.new()
	enemy.entity_id = "stack_enemy"
	root.add_child(enemy)
	await process_frame
	_assert(enemy.aura_component != null and enemy.combat_component != null, "fighter gains aura + combat components")
	if es:
		es.register_entity(carrier, null, "stack_carrier")
		es.register_entity(enemy, null, "stack_enemy")

	# --- 2. Canonical routing through the aura mirror --------------------------
	var debuff_applied := {"n": 0}
	var debuff_removed := {"n": 0}
	if hub:
		hub.debuff_applied.connect(func(_e, _b, _s): debuff_applied["n"] += 1)
		hub.debuff_removed.connect(func(_e, _b): debuff_removed["n"] += 1)

	var poison = StatusScript.new()
	poison.effect_id = "live_poison"
	poison.effect_name = "Live Poison"
	poison.effect_type = StatusScript.EffectType.DEBUFF
	poison.effect_category = StatusScript.EffectCategory.POISON
	poison.duration = 5.0
	carrier.apply_status_effect(poison)
	_assert(carrier.status_effects.has(poison), "canonical store holds the applied effect")
	_assert(carrier.aura_component.get_debuff_count() == 1, "aura mirror tracks the debuff")
	_assert(debuff_applied["n"] == 1, "EventHub.debuff_applied fired on the live path")
	carrier.remove_status_effect(poison)
	_assert(not carrier.status_effects.has(poison) and carrier.aura_component.get_debuff_count() == 0, "canonical removal untracks the mirror")
	_assert(debuff_removed["n"] == 1, "EventHub.debuff_removed fired on removal")

	# --- 3. Dispel path (fixed category read + collect-then-remove) ------------
	var curse = StatusScript.new()
	curse.effect_id = "live_curse"
	curse.effect_name = "Live Curse"
	curse.effect_type = StatusScript.EffectType.DEBUFF
	curse.effect_category = StatusScript.EffectCategory.CURSE
	curse.duration = 5.0
	carrier.apply_status_effect(curse)
	_assert(carrier.aura_component.dispel_poison(null) == 0, "dispel_poison skips a CURSE debuff")
	_assert(carrier.aura_component.dispel_debuffs("curse") == 1, "category dispel removes the curse")
	_assert(carrier.aura_component.get_debuff_count() == 0, "mirror empty after dispel")

	# --- 4. DoT lands + ticks + self-expires (the live applier) ----------------
	var victim: Node = EntityScript.new()
	victim.entity_id = "dot_victim"
	root.add_child(victim)
	await process_frame
	var hp0: int = int(victim.current_health)

	var dot_skill = SkillScript.new()
	dot_skill.skill_id = "live_dot"
	dot_skill.skill_name = "Live Dot"
	dot_skill.is_dot = true
	dot_skill.dot_damage = 5
	dot_skill.dot_duration = 0.2
	dot_skill.dot_tick_rate = 0.05
	dot_skill.applyDoT(carrier, victim)
	_assert(victim.status_effects.size() == 1, "DoT applied through the live applier")
	await create_timer(0.5).timeout
	_assert(int(victim.current_health) <= hp0 - 5, "DoT ticks drained health")
	_assert(victim.status_effects.is_empty(), "DoT self-expired after its tick budget")

	# --- 5. DoT on the player (3-arg signal family) ----------------------------
	var player: Node = PlayerScript.new()
	player.entity_id = "stack_player"
	root.add_child(player)
	await process_frame
	_assert(player.aura_component != null and player.combat_component != null, "player carries the combat effect stack")
	_assert(player.health_component != null, "player health component ready")
	var php0: int = int(player.health_component.current_health)
	dot_skill.applyDoT(carrier, player)
	_assert(player.status_effects.size() == 1, "DoT lands on the player")
	await create_timer(0.5).timeout
	_assert(int(player.health_component.current_health) < php0, "player DoT ticked through take_damage")
	_assert(player.status_effects.is_empty(), "player DoT expired cleanly")

	# --- 6. CC stores and expires (perma-stun fix) -----------------------------
	var cc_skill = SkillScript.new()
	cc_skill.skill_id = "live_stun"
	cc_skill.skill_name = "Live Stun"
	cc_skill.crowd_control_type = "stun"
	cc_skill.crowd_control_duration = 0.1
	var stun = cc_skill.create_stun_effect(carrier)
	_assert(stun.tick_behavior == StatusScript.TickBehavior.DURATION, "CC effects are DURATION behavior (expire)")
	carrier.apply_status_effect(stun)
	_assert(carrier.status_effects.has(stun), "stun stored")
	await create_timer(0.4).timeout
	_assert(carrier.status_effects.is_empty(), "stun expired (no more perma-CC)")

	# --- 7. CombatComponent gate on the player ---------------------------------
	var self_skill = SkillScript.new()
	self_skill.skill_id = "live_self"
	self_skill.skill_name = "Live Self"
	self_skill.skill_type = SkillScript.SkillType.SELF
	self_skill.mana_cost = 0
	var cast_ok: bool = player.combat_component.execute_skill(self_skill, null)
	_assert(cast_ok, "player cast routes through the combat component")
	_assert(player.combat_component.gcd_remaining > 0.0, "GCD started on cast")
	_assert(not player.combat_component.execute_skill(self_skill, null), "GCD blocks the immediate recast")

	# --- 8. Hitbox-family routing preserves CombatSystem execution -------------
	var melee = SkillScript.new()
	melee.skill_id = "live_melee"
	melee.skill_name = "Live Melee"
	melee.skill_type = SkillScript.SkillType.MELEE
	melee.damage = 3
	melee.hitbox_size = 0.0
	melee.mana_cost = 0
	var mhp0: int = int(carrier.current_health)
	var melee_ok: bool = enemy.combat_component.execute_skill(melee, carrier)
	_assert(melee_ok, "melee cast routes through the component")
	_assert(enemy.combat_component.gcd_remaining > 0.0, "melee cast started the GCD")
	_assert(int(carrier.current_health) < mhp0, "melee damage landed through CombatSystem.execute_skill")

	# --- 9. Defer flag: hitbox casts do not double-apply at cast time ----------
	var defer_skill = SkillScript.new()
	defer_skill.skill_id = "live_defer"
	defer_skill.skill_name = "Live Defer"
	defer_skill.is_dot = true
	defer_skill.dot_damage = 2
	defer_skill.dot_duration = 0.2
	defer_skill.dot_tick_rate = 0.05
	var deferred: Dictionary = defer_skill.execute(enemy, carrier, Vector3.ZERO, true)
	_assert(deferred.get("success", false), "deferred cast succeeds")
	_assert(carrier.status_effects.is_empty(), "deferred cast applies no target effects at cast time")
	defer_skill.execute(enemy, carrier, Vector3.ZERO, false)
	_assert(carrier.status_effects.size() == 1, "un-deferred cast applies the DoT (landed-hit path parity)")

	_finish()

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("CombatStackLive: %d passed, %d failed" % [_pass, _fail])
