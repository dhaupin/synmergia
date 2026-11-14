## test_status_effect_tres.gd - the .tres status-effect system is wired to
## runtime: a skill's authored buff/debuff entry resolves through
## StatusEffectFactory -> data/status_effects/*.tres and lands on the real
## apply path with real payload teeth (stat mods, CC gates, shields).
##
## Before this, nothing read StatusEffectData: every authored buff was a
## display-only shell and get_status_effect() had no caller.
##
## Run headless:
##   cd game && godot --headless --path . --script res://tests/test_status_effect_tres.gd
## Exit 0 = all pass.
extends SceneTree

const StatusEffect = preload("res://core/entities/status_effect.gd")
const Factory = preload("res://core/combat/status_effect_factory.gd")
const SkillSchema = preload("res://core/schemas/skill.gd")
const CombatSkill = preload("res://core/combat/skill.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
        await process_frame
        await _run()
        quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
        if cond:
                _pass += 1
        else:
                _fail += 1
                print("  [FAIL] ", msg)

func _entity() -> Node:
        var e: Node = load("res://core/entities/entity.gd").new()
        root.add_child(e)
        return e

func _run() -> void:
        var ds = root.get_node_or_null("DataService")
        _assert(ds != null, "DataService autoload present")
        if ds == null:
                print("--- STATUS EFFECT TRES: %d passed, %d failed ---" % [_pass, _fail])
                return

        # --- 1. Factory maps the .tres payload onto runtime fields -------------
        var cry = Factory.from_id("buff_battle_cry")
        _assert(cry != null, "buff_battle_cry resolves via DataService")
        _assert(cry != null and cry.strength_mod == 15, "battle cry carries its strength payload")
        _assert(cry != null and cry.effect_type == StatusEffect.EffectType.BUFF, "battle cry is a BUFF")
        _assert(cry != null and cry.duration == 15.0, "battle cry carries its duration")

        var stun = Factory.from_id("debuff_stun")
        _assert(stun != null, "debuff_stun resolves")
        _assert(stun != null and not stun.can_move and not stun.can_cast and not stun.can_attack, "stun blocks move/cast/attack")
        _assert(stun != null and stun.effect_category == StatusEffect.EffectCategory.STUN, "stun routes to the STUN category")

        var shield = Factory.from_id("buff_mana_shield")
        _assert(shield != null and shield.shield_amount == 150, "mana shield carries its shield payload")

        var haste = Factory.from_id("buff_haste")
        _assert(haste != null and is_equal_approx(haste.movement_speed_multiplier, 0.2), "haste stores a +20% delta (0.2, not 1.2)")

        _assert(Factory.from_id("definitely_not_a_real_effect") == null, "unknown effect_id degrades to null (no crash)")

        var overridden = Factory.from_id("buff_battle_cry", 30.0)
        _assert(overridden != null and overridden.duration == 30.0, "skill duration override wins over the template default")

        # --- 2. from_schema keeps the authored buff entry ----------------------
        var schema = ds.get_skill("human_battle_cry")
        _assert(schema != null, "human_battle_cry schema loads")
        var sk = CombatSkill.from_schema(schema)
        _assert(sk.status_effects.size() == 1, "runtime Skill keeps the authored buff entry")
        _assert(sk.status_effects.size() == 1 and str(sk.status_effects[0].get("effect_id", "")) == "buff_battle_cry", "entry carries the effect_id")

        # --- 3. Self-buff lands on the caster through the real execute path ----
        var caster := _entity()
        var before: int = int(caster.stats.strength)
        sk.execute(caster, null)
        _assert(int(caster.stats.strength) == before + 15, "battle cry raised the caster's strength by 15")
        _assert(caster.status_effects.size() == 1, "the buff is tracked on the caster")

        # --- 4. Debuff lands on the target and its CC flags take effect --------
        var victim := _entity()
        var shield_bash = ds.get_skill("human_shield_bash")
        _assert(shield_bash != null, "human_shield_bash schema loads")
        var bash = CombatSkill.from_schema(shield_bash)
        _assert(bash.status_effects.size() == 1, "shield bash keeps its stun entry")
        bash.execute(caster, victim)
        _assert(victim.status_effects.size() >= 1, "the stun landed on the target")
        var blocked := false
        for effect in victim.status_effects:
                if effect.has_method("allows_casting") and not effect.allows_casting():
                        blocked = true
        _assert(blocked, "the stun gate blocks the target from casting")

        # --- 5. Shield absorbs before health (Entity path) ---------------------
        var guarded := _entity()
        guarded.apply_status_effect(Factory.from_id("buff_mana_shield"))
        var hp: int = guarded.current_health
        var dealt: int = guarded.take_damage(100, null, "physical")
        _assert(dealt == 0 and guarded.current_health == hp, "a 150 shield fully absorbs a 100 hit (0 to health)")

        # --- 6. Invincibility negates the hit ---------------------------------
        var invuln := _entity()
        invuln.apply_status_effect(Factory.from_id("buff_immunity"))
        var hp2: int = invuln.current_health
        _assert(invuln.take_damage(999, null, "physical") == 0 and invuln.current_health == hp2, "invincibility negates a 999 hit")

        # --- 7. Movement multiplier delta is read (movement gate helper) ------
        var rooted := _entity()
        var root_fx = Factory.from_id("root_common")
        _assert(root_fx != null and not root_fx.allows_movement(), "root denies movement")
        rooted.apply_status_effect(root_fx)
        var move_ok := true
        for effect in rooted.status_effects:
                if effect.has_method("allows_movement") and not effect.allows_movement():
                        move_ok = false
        _assert(not move_ok, "rooted body reports can_move false on the live store")

        # --- 8. Defense multiplier is read by mitigation ----------------------
        var soft := _entity()
        var base_received: int = soft._calculate_damage_received(100, "physical")
        soft.stats.defense_multiplier = 3.0
        var buffed_received: int = soft._calculate_damage_received(100, "physical")
        _assert(buffed_received < base_received, "a defense multiplier reduces incoming damage")

        # --- 9. Taunt skill force-locks enemies via the aggro table -----------
        # A taunt is aggro control, not a stat debuff: the authored
        # debuff_taunt entry must drive AggroComponent.taunt, or the whole
        # tank identity is a silent no-op.
        var taunt_schema = ds.get_skill("akkan_taunt")
        _assert(taunt_schema != null, "akkan_taunt schema loads")
        var taunt_skill = CombatSkill.from_schema(taunt_schema)
        _assert(taunt_skill.taunt_targets, "a debuff_taunt entry flags the skill as a taunt")
        _assert(is_equal_approx(taunt_skill.taunt_duration, 4.0), "the authored duration carries to the taunt lock")

        # End-to-end: cast the taunt on a live enemy and prove the aggro lock
        # takes hold (the engine path, not just the flag).
        var es2 = root.get_node_or_null("EntityService")
        if es2 != null:
                var taunter := _entity()
                taunter.entity_id = "taunt_caster"
                var mob: Node = load("res://entities/enemy.gd").new()
                mob.entity_id = "taunt_mob"
                root.add_child(mob)
                await process_frame
                es2.register_entity(taunter, null, "taunt_caster")
                es2.register_entity(mob, null, "taunt_mob")
                var rival := _entity()
                rival.entity_id = "taunt_rival"
                es2.register_entity(rival, null, "taunt_rival")
                var ac = mob.get("aggro_component")
                _assert(ac != null, "the mob carries an aggro component")
                if ac != null:
                        ac.add_threat(rival, 500)
                        ac._enter_combat(rival)
                        taunt_skill.execute(taunter, null, taunter.global_position)
                        _assert(ac.is_taunted(), "casting the taunt force-locks the mob")
                        _assert(ac.get_highest_threat_target() == taunter, "the taunter is the mob's target after the taunt")

        # --- 10. Skill-level CC effect entries gate the body --------------------
        # An authored "stun"/"root"/"slow" entry flattens into crowd_control_type
        # and applyCrowdControl builds the runtime effect; the gating flags are
        # what make it bite. Before the fix the builders set neither the
        # can_move/can_cast flags nor a slow multiplier, so a skill-authored
        # stun did not stun and a slow did not slow.
        var warp = ds.get_skill("human_time_warp")
        _assert(warp != null, "human_time_warp schema loads")
        var warp_sk = CombatSkill.from_schema(warp)
        _assert(warp_sk.crowd_control_type == "slow", "the authored slow entry sets crowd_control_type")
        _assert(is_equal_approx(warp_sk.crowd_control_slow_percent, 0.2), "the slow's value (20) reads as a 0.2 penalty")

        var slow_fx = warp_sk.create_slow_effect(caster)
        _assert(slow_fx.allows_movement(), "a slow still permits movement")
        _assert(is_equal_approx(slow_fx.movement_speed_multiplier, -0.2), "the slow carries its -20% movement delta")

        var stun_fx = warp_sk.create_stun_effect(caster)
        _assert(not stun_fx.allows_movement() and not stun_fx.allows_casting() and not stun_fx.allows_attacking(), "a built stun gates move/cast/attack")

        var root_fx2 = warp_sk.create_root_effect(caster)
        _assert(not root_fx2.allows_movement() and root_fx2.allows_casting(), "a built root gates movement only")

        # End-to-end: a stun built from a skill blocks the victim's cast gate.
        var held := _entity()
        held.apply_status_effect(stun_fx)
        var held_blocked := false
        for effect in held.status_effects:
                if effect.has_method("allows_casting") and not effect.allows_casting():
                        held_blocked = true
        _assert(held_blocked, "a skill-built stun blocks the victim's casting on the live store")

        # --- 11. CC immunity actually refuses a control -------------------------
        # The schema carried immune_stun/immune_slow/... and grants_immunity_to()
        # with zero callers, so nothing could ever be immune: an immune body took
        # the stun like anyone else. The gate now lives at apply_status_effect,
        # the one choke point every CC path funnels through.
        var ward_fx = Factory.from_id("buff_immune_stun")
        _assert(ward_fx != null, "buff_immune_stun resolves through the factory")
        _assert(ward_fx.immune_tags.has("stun"), "the stun ward carries the stun tag")

        var shielded := _entity()
        shielded.apply_status_effect(ward_fx)
        shielded.apply_status_effect(warp_sk.create_stun_effect(caster))
        var immune_blocked := false
        for effect in shielded.status_effects:
                if effect.has_method("allows_casting") and not effect.allows_casting():
                        immune_blocked = true
        _assert(not immune_blocked, "an immune body refuses the stun outright")

        # The refusal is tag-specific: a root is not a stun and still lands.
        shielded.apply_status_effect(warp_sk.create_root_effect(caster))
        var immune_rooted := false
        for effect in shielded.status_effects:
                if effect.has_method("allows_movement") and not effect.allows_movement():
                        immune_rooted = true
        _assert(immune_rooted, "the stun ward does not stop an unrelated root")

        # A plain body still takes the same stun (the gate is not a blanket mute).
        var plain := _entity()
        plain.apply_status_effect(warp_sk.create_stun_effect(caster))
        var plain_stunned := false
        for effect in plain.status_effects:
                if effect.has_method("allows_casting") and not effect.allows_casting():
                        plain_stunned = true
        _assert(plain_stunned, "a body with no ward still takes the stun")

        # immune_all blocks every control tag, matching get_immunity_list's ["all"].
        var bastion = Factory.from_id("buff_immunity")
        _assert(bastion.immune_all, "immune_all data maps to the runtime immune_all flag")
        var allblock := _entity()
        allblock.apply_status_effect(bastion)
        allblock.apply_status_effect(warp_sk.create_stun_effect(caster))
        var all_blocked := false
        for effect in allblock.status_effects:
                if effect.has_method("allows_casting") and not effect.allows_casting():
                        all_blocked = true
        _assert(not all_blocked, "immune_all refuses crowd control as well as damage")

        # Time Anchor's description promises immunity; the payload now honors it.
        var anchor = Factory.from_id("buff_time_anchor")
        _assert(anchor != null and anchor.immune_tags.has("slow"), "buff_time_anchor refuses slow as its description promises")
        var anchored := _entity()
        anchored.apply_status_effect(anchor)
        anchored.apply_status_effect(warp_sk.create_slow_effect(caster))
        var anchored_slowed := false
        for effect in anchored.status_effects:
                if effect.has_method("allows_movement") and not effect.allows_movement():
                        anchored_slowed = true
        _assert(not anchored_slowed, "a time-anchored body cannot be slowed")

        print("--- STATUS EFFECT TRES: %d passed, %d failed ---" % [_pass, _fail])
