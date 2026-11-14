## test_stat_modifiers.gd - the canonical StatId vocabulary and the
## mitigation/reflect damage pipeline are wired end to end:
##
##   1. StatId is the one stat registry (primaries, multipliers, flat
##      deltas) and every authored .tres key names a real stat.
##   2. damage_reduction trims an incoming hit on both the Entity and the
##      player (health_component) path.
##   3. damage_reflect sends a fraction of a landed hit back to the
##      attacker, and the reflected school stops a two-barrier ping-pong.
##   4. A status effect authored with damage_reduction/damage_reflect
##      reaches the entity stats block through the factory.
##
## Run headless:
##   cd game && godot --headless --path . --script res://tests/test_stat_modifiers.gd
## Exit 0 = all pass.
extends SceneTree

const StatId = preload("res://core/schemas/stat_id.gd")
const Factory = preload("res://core/combat/status_effect_factory.gd")
const StatusEffectDataScript = preload("res://core/schemas/status_effect_data.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
        await process_frame
        await _run()
        print("--- STAT MODIFIERS: %d passed, %d failed ---" % [_pass, _fail])
        quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
        if cond:
                _pass += 1
        else:
                _fail += 1
                print("  [FAIL] ", msg)

## A bare body with a large health pool. max_health is set AFTER add_child
## because _ready recomputes it from vitality (100 + vitality*8), and a small
## pool would die mid-test.
func _entity() -> Node:
        var e: Node = load("res://core/entities/entity.gd").new()
        root.add_child(e)
        e.max_health = 100000
        e.current_health = 100000
        return e

## Zero a body's defense curve by writing the stats dict directly (never
## set_stat, which would recompute max_health). Lets a test read the new
## mitigation/reflect keys without the base armor curve in the way.
func _no_defense(e) -> void:
        e.stats["vitality"] = 0
        e.stats["wisdom"] = 0

func _run() -> void:
        # --- 1. StatId vocabulary -------------------------------------------
        _assert(StatId.is_valid("strength"), "strength is a stat")
        _assert(StatId.is_valid("damage_reduction"), "damage_reduction is a stat")
        _assert(StatId.is_valid("damage_reflect"), "damage_reflect is a stat")
        _assert(StatId.is_valid("health_regen"), "health_regen is a stat")
        _assert(not StatId.is_valid("bogus_stat"), "an unknown key is not a stat")
        _assert(StatId.is_primary("vitality"), "vitality is a primary")
        _assert(not StatId.is_primary("damage_reduction"), "damage_reduction is not a primary")
        _assert(StatId.is_multiplicative("defense_multiplier"), "defense_multiplier is multiplicative")
        _assert(not StatId.is_multiplicative("damage_reflect"), "damage_reflect is a flat delta")
        _assert(StatId.default_of("strength") == 10.0, "primary default is 10")
        _assert(StatId.default_of("damage_multiplier") == 1.0, "multiplier default is 1.0")
        _assert(StatId.default_of("damage_reduction") == 0.0, "flat delta default is 0.0")
        var block := StatId.base_block()
        _assert(block.size() == StatId.ALL.size(), "base_block seeds every stat key")
        _assert(block["damage_reflect"] == 0.0 and block["wisdom"] == 10, "base_block has canonical defaults")
        _assert(StatId.clamp_fraction("damage_reduction", 5.0) == StatId.MAX_DAMAGE_REDUCTION, "reduction clamps to its ceiling")
        _assert(StatId.clamp_fraction("damage_reflect", 5.0) == StatId.MAX_DAMAGE_REFLECT, "reflect clamps to its ceiling")

        # Entity's own stats block carries every StatId key (no drift).
        var e0 := _entity()
        for key in StatId.ALL:
                _assert(e0.stats.has(key), "entity stats carry StatId key '%s'" % key)

        # --- 2. damage_reduction trims a hit --------------------------------
        # Two identical bodies: the baseline body has no reduction, the other
        # 50%. Comparing the two isolates the new key from the base defense
        # curve (which the bare entity also applies).
        var plain := _entity()
        var target := _entity()
        var baseline: int = plain.take_damage(200, null, "true")
        target.stats["damage_reduction"] = 0.50
        var reduced: int = target.take_damage(200, null, "true")
        _assert(reduced == int(baseline * 0.5),
                "50%% reduction halves the hit (baseline %d -> %d)" % [baseline, reduced])

        # Reduction is clamped: 5.0 authored still leaves chip damage.
        var clamp_body := _entity()
        clamp_body.stats["damage_reduction"] = 5.0
        var clamped: int = clamp_body.take_damage(200, null, "true")
        _assert(clamped >= 1 and clamped <= int(baseline * 0.11),
                "reduction is clamped near its ceiling (got %d vs baseline %d)" % [clamped, baseline])

        # --- 3. damage_reflect answers the attacker --------------------------
        var attacker := _entity()
        var defender := _entity()
        _no_defense(attacker)
        _no_defense(defender)
        defender.stats["damage_reflect"] = 0.25
        var hp_before: int = attacker.current_health
        var landed: int = defender.take_damage(200, attacker, "true")
        _assert(attacker.current_health == hp_before - int(landed * 0.25),
                "reflect sends 25%% of the landed hit back (attacker %d -> %d)" % [hp_before, attacker.current_health])

        # The reflected school does not itself reflect: no ping-pong.
        var a2 := _entity()
        var b2 := _entity()
        _no_defense(a2)
        _no_defense(b2)
        a2.stats["damage_reflect"] = 1.0
        b2.stats["damage_reflect"] = 1.0
        var a2_hp: int = a2.current_health
        var b2_hp: int = b2.current_health
        var b2_landed: int = b2.take_damage(200, a2, "true")
        _assert(a2.current_health == a2_hp - b2_landed, "one bounce lands on the attacker")
        _assert(b2.current_health == b2_hp - b2_landed, "the reflected hit does not bounce back to the defender")

        # Self-damage never reflects onto itself.
        var solo := _entity()
        _no_defense(solo)
        solo.stats["damage_reflect"] = 0.5
        var solo_hp: int = solo.current_health
        var solo_landed: int = solo.take_damage(80, solo, "true")
        _assert(solo.current_health == solo_hp - solo_landed, "a self-hit does not reflect (no double dip)")

        # --- 4. Factory maps authored payloads --------------------------------
        var reflect_data = StatusEffectDataScript.new()
        reflect_data.id = "test_reflect"
        reflect_data.damage_reflect = 0.40
        var fx = Factory.from_data(reflect_data)
        _assert(fx != null and is_equal_approx(fx.damage_reflect, 0.40), "factory maps damage_reflect")
        _assert(fx != null and fx.damage_reduction == 0.0, "factory leaves an unauthored reduction at 0")

        var reduce_data = StatusEffectDataScript.new()
        reduce_data.id = "test_reduce"
        reduce_data.damage_reduction = 0.30
        var fx2 = Factory.from_data(reduce_data)
        _assert(fx2 != null and is_equal_approx(fx2.damage_reduction, 0.30), "factory maps damage_reduction")

        # A status effect's payload reaches the entity stats block on apply.
        var bearer := _entity()
        var fx3 = Factory.from_id("buff_reflect")
        _assert(fx3 != null, "buff_reflect resolves via DataService")
        if fx3 != null:
                bearer.apply_status_effect(fx3)
                _assert(is_equal_approx(float(bearer.stats.get("damage_reflect", 0.0)), 0.30),
                        "an applied reflect effect lands on the entity stats block")
                bearer.remove_status_effect(fx3)
                _assert(is_equal_approx(float(bearer.stats.get("damage_reflect", 0.0)), 0.0),
                        "removing the effect clears the stats delta")

        # --- 5. Every authored stat key names a real StatId key ---------------
        # The phantom-field lint checks depth-0 .tres keys only, so an unknown
        # key INSIDE a stat_modifiers/stat_multipliers dict is silently inert.
        # This is the leg that closes that hole across every status effect.
        var bad: Array = []
        var dir := DirAccess.open("res://data/status_effects")
        var checked := 0
        if dir != null:
                dir.list_dir_begin()
                var f := dir.get_next()
                while f != "":
                        if f.ends_with(".tres"):
                                var txt := FileAccess.get_file_as_string("res://data/status_effects/%s" % f)
                                checked += 1
                                for key in _dict_keys(txt, "stat_modifiers"):
                                        if not StatId.is_valid(key):
                                                bad.append("%s stat_modifiers['%s']" % [f, key])
                                for key2 in _dict_keys(txt, "stat_multipliers"):
                                        if not StatId.is_valid(key2):
                                                bad.append("%s stat_multipliers['%s']" % [f, key2])
                        f = dir.get_next()
        _assert(checked > 0, "found status effects to lint (%d)" % checked)
        _assert(bad.is_empty(), "every authored stat key is a real StatId key: %s" % ", ".join(bad))


## Pull the quoted keys out of a one-line `field = {"a": 1, "b": 2}` dict.
func _dict_keys(txt: String, field: String) -> Array:
        var keys: Array = []
        var re := RegEx.new()
        re.compile("^%s = \\{(.*)\\}$" % field)
        for line in txt.split("\n"):
                var m := re.search(line)
                if m == null:
                        continue
                for pair in m.get_string(1).split(","):
                        var km := RegEx.new()
                        km.compile("\"([a-z_]+)\"")
                        var k := km.search(pair)
                        if k != null:
                                keys.append(k.get_string(1))
        return keys
