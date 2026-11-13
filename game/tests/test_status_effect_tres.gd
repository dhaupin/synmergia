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

        print("--- STATUS EFFECT TRES: %d passed, %d failed ---" % [_pass, _fail])
