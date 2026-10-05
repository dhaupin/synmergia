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
	var effect_added := {"n": 0}
	var effect_removed := {"n": 0}
	if hub:
		hub.debuff_applied.connect(func(_e, _b, _s): debuff_applied["n"] += 1)
		hub.debuff_removed.connect(func(_e, _b): debuff_removed["n"] += 1)
		hub.entity_effect_added.connect(func(eid, data):
			effect_added["n"] += 1
			if eid == "stack_carrier":
				effect_added["last_id"] = data.get("id", "")
				effect_added["last_debuff"] = data.get("is_debuff", false))
		hub.entity_effect_removed.connect(func(eid, eff_id):
			effect_removed["n"] += 1
			if eid == "stack_carrier":
				effect_removed["last_id"] = eff_id)

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
	_assert(effect_added["n"] == 1 and effect_added["last_id"] == "live_poison" and effect_added["last_debuff"] == true, "target-frame snapshot rides the same apply (R29)")
	carrier.remove_status_effect(poison)
	_assert(not carrier.status_effects.has(poison) and carrier.aura_component.get_debuff_count() == 0, "canonical removal untracks the mirror")
	_assert(debuff_removed["n"] == 1, "EventHub.debuff_removed fired on removal")
	_assert(effect_removed["n"] == 1 and effect_removed["last_id"] == "live_poison", "target-frame removal rides the same untrack (R29)")

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
	# The hit table is ONE randf() consumed synchronously inside the cast
	# -- seed immediately before so the roll is deterministic (the old
	# unseeded cast flaked ~5-10% of runs on a miss-family outcome).
	seed(20261005)
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

	# --- 10. EnemyAI skill casting through the component (R29) ------------------
	var EnemyDataScript = load("res://core/schemas/enemy_data.gd")
	var AIScript = load("res://core/ai/enemy_ai.gd")
	_assert(AIScript != null and EnemyDataScript != null, "AI + EnemyData scripts resolvable")
	# Let section 9's DoT run out so the array counts below are exact.
	await create_timer(0.5).timeout

	var kit_enemy: Node = EnemyScript.new()
	var ed = EnemyDataScript.new()
	var kit_ids: Array[String] = ["human_smite"]  # typed: the export is Array[String]
	ed.skills = kit_ids
	kit_enemy.enemy_data = ed
	kit_enemy.entity_id = "kit_enemy"
	root.add_child(kit_enemy)
	await process_frame
	_assert(kit_enemy.combat_component != null, "kit enemy carries the combat component")
	# The hitbox sweep only sees CombatSystem's own registry (the live
	# spawn flow registers both families there).
	var combat_sys = root.get_node_or_null("CombatSystem")
	if combat_sys:
		combat_sys.register_entity(carrier)

	var kit_ai = AIScript.new()
	kit_enemy.attach_ai(kit_ai)
	kit_ai._target = carrier
	kit_ai._attack_timer = 0.0
	# Deterministic kit: an injected DoT skill (cast-time effects are not
	# whiff-gated) exercises the component path end to end without RNG.
	var ai_dot = SkillScript.new()
	ai_dot.skill_id = "ai_dot"
	ai_dot.skill_name = "AI Dot"
	ai_dot.is_dot = true
	ai_dot.dot_damage = 3
	# Long enough to survive the sweep window AND the tick janitor's
	# wall-clock advance of TICKED effects (a 0.2s DoT is swept before
	# the assert window closes).
	ai_dot.dot_duration = 2.0
	ai_dot.dot_tick_rate = 0.05
	kit_ai._skills = [ai_dot]
	kit_ai._skills_loaded = true
	kit_ai._perform_attack()
	_assert(kit_enemy.combat_component.gcd_remaining > 0.0, "AI cast routed through the component (GCD)")
	# The kit skill kept its default hitbox, so the DoT lands through the
	# sweep (defer_target_effects) a physics frame or two later -- the
	# TRUE live path: AI -> component -> CombatSystem -> landed-hit effects.
	var hp_before_sweep: int = int(carrier.current_health)
	await create_timer(0.3).timeout
	_assert(carrier.status_effects.size() == 1, "AI DoT landed through the hitbox sweep + live stack")
	_assert(int(carrier.current_health) < hp_before_sweep, "AI DoT ticks drained health on the live path")
	carrier.clear_all_status_effects()

	# Data materialization: EnemyData.skills -> combat Skills via DataService.
	kit_ai._skills = []
	kit_ai._skills_loaded = false
	kit_ai._load_skills()
	_assert(kit_ai._skills.size() == 1 and kit_ai._skills[0].skill_id == "human_smite", "EnemyData.skills materialize into combat Skills")
	_assert(kit_ai._skills[0].required_class == "human_cleric", "schema class gate carried into the combat Skill")
	_assert(kit_ai._next_ready_skill(kit_enemy) == null, "class-locked kit skill correctly not castable by a classless enemy")

	# --- 11. BuffBar handler contract (R29 follow-up) ---------------------------
	# The HUD handlers read effect_id/duration off live StatusEffects
	# (the old .get("id") reads returned nothing -- the bar never
	# rendered). Probed with a stub bar, no scene deps.
	var HudIntScript = load("res://ui/hud/hud_integrator.gd")
	var bar_integ: Node = HudIntScript.new()  # not in tree: _ready-free
	# Duck-typed stub bar (add_buff/remove_buff recorded on itself).
	var BarProbe: Node = load("res://tests/stub_buff_bar.gd").new()
	bar_integ._buff_bar = BarProbe
	var bar_buff = StatusScript.new()
	bar_buff.effect_id = "bar_buff"
	bar_buff.effect_name = "Bar Buff"
	bar_buff.effect_type = StatusScript.EffectType.BUFF
	bar_buff.duration = 3.0
	bar_integ._on_buff_added(bar_buff)
	bar_integ._on_debuff_added(bar_buff)
	bar_integ._on_buff_removed(bar_buff)
	var bar_added: Array = BarProbe.added
	var bar_removed: Array = BarProbe.removed
	_assert(bar_added.size() == 2 and bar_added[0]["id"] == "bar_buff" and bar_added[0]["debuff"] == false and bar_added[1]["debuff"] == true, "buff/debuff handlers read effect_id and polarity correctly")
	_assert(float(bar_added[0]["duration"]) == 3.0, "handler duration survives the duck-typed read")
	_assert(bar_removed.size() == 1 and bar_removed[0] == "bar_buff", "removal handler keys off effect_id")
	# Binding: the stack-attached aura component (auto-named node) is
	# found via the entity field / script-class scan, not the old
	# get_class() check that never matched.
	var pm = root.get_node_or_null("PlayerManager")
	if pm:
		pm.local_player = carrier
		bar_integ._bind_aura_signals()
		_assert(carrier.aura_component.buff_added.is_connected(bar_integ._on_buff_added), "_bind_aura_signals finds the stack-attached aura component")
		pm.local_player = null
	bar_integ.free()
	BarProbe.free()

	# --- 12. DoT kills attribute + trigger the real death flow (R31) ------------
	# Ticks route through the target's take_damage with the effect's
	# source: a killing tick must trigger the REAL death chain (die ->
	# corpse/loot/kill-rewards/unregister) and pay the CASTER -- the old
	# direct health mutation left 0-HP zombies and unattributed kills.
	var kr_victim: Node = EnemyScript.new()
	var kr_data = EnemyDataScript.new()
	kr_victim.enemy_data = kr_data
	kr_victim.entity_id = "dot_kill_victim"
	root.add_child(kr_victim)
	await process_frame
	var dot_caster: Node = EntityScript.new()
	dot_caster.entity_id = "dot_caster"
	root.add_child(dot_caster)
	await process_frame
	var kill_capt := {"n": 0, "killer": null, "xp": -1}
	var died_n := {"n": 0}
	var died_is_dead: Array = []
	if hub:
		hub.kill_rewarded.connect(func(_entity, killer, rewards):
			kill_capt["n"] += 1
			kill_capt["killer"] = killer
			kill_capt["xp"] = int(rewards.get("xp", 0)))
	# Capture death state INSIDE the death signal: the full death chain
	# frees the node (despawn), so post-wait asserts must not touch it.
	# The Enemy family dies through health_component.die()'s chain --
	# the base Entity.died signal never fires for it; EventHub.entity_died
	# is the authoritative death event for BOTH families.
	if hub:
		hub.entity_died.connect(func(entity, _killer, _meta):
			died_n["n"] += 1
			if entity != null and is_instance_valid(entity) and "is_dead" in entity:
				died_is_dead.append(bool(entity.is_dead)))
	var kill_dot = SkillScript.new()
	kill_dot.skill_id = "kill_dot"
	kill_dot.skill_name = "Kill Dot"
	kill_dot.is_dot = true
	kill_dot.dot_damage = 99999
	kill_dot.dot_duration = 1.0
	kill_dot.dot_tick_rate = 0.05
	kill_dot.applyDoT(dot_caster, kr_victim)
	_assert(kr_victim.status_effects.size() == 1, "lethal DoT applied to the enemy")
	_assert(kr_victim.status_effects[0].source == dot_caster, "DoT carries its caster as source")
	await create_timer(0.4).timeout
	_assert(died_n["n"] >= 1 and not died_is_dead.is_empty() and bool(died_is_dead[0]), "killing tick triggered the real death flow with is_dead set (no 0-HP zombie)")
	_assert(not is_instance_valid(kr_victim), "dead enemy freed by the despawn path")
	_assert(kill_capt["n"] == 1 and kill_capt["killer"] == dot_caster, "DoT kill credited to the caster via kill_rewarded")
	_assert(kill_capt["xp"] > 0, "DoT kill paid XP")
	if es:
		_assert(es.get_entity("dot_kill_victim") == null, "dead enemy unregistered (despawn path)")
	if is_instance_valid(kr_victim):
		kr_victim.queue_free()
	dot_caster.queue_free()

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
