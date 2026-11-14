extends SceneTree

## Scope bands -- the upgrade TIER -> REACH ladder.
##
## The upgrade ladder scaled numbers (damage_mult, range_mult, ...) but could
## not express a skill that changes KIND as it climbs. ScopeBand owns that:
##
##   1. A heal is single-target until the epic band, then a friendly AoE with
##      no cap at the top (owner: "aoe bands at upgrades epic and higher, all
##      friendlies healed, no limit at high tier").
##   2. A teleport reaches further each tier and crosses scopes (instance ->
##      world -> planet) at mythic.
##
## Checks the pure tables, the Skill wiring (apply_scope_bands), and a LIVE
## banded heal over the real EntityService sweep: friends are mended, the
## enemy in the same radius is not.
##
## Run: godot --headless --path . --script res://tests/test_scope_bands.gd

const ScopeBand = preload("res://core/combat/scope_band.gd")
const CombatSkill = preload("res://core/combat/skill.gd")
const EntityScript = preload("res://core/entities/entity.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
        call_deferred("_run")

func _ok(msg: String) -> void:
        _passed += 1
        print("  [OK] ", msg)

func _fail(msg: String) -> void:
        _failed += 1
        print("  [FAIL] ", msg)

func _finish() -> void:
        print("--- SCOPE BANDS: %d passed, %d failed ---" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)

func _run() -> void:
        # --- 1. The heal band: single-target -> friendly AoE at epic ---
        if not ScopeBand.heal_is_aoe(0) and not ScopeBand.heal_is_aoe(2):
                _ok("a heal is single-target through the rare band (levels 0-2)")
        else:
                _fail("a heal went AoE before the epic band")
        if ScopeBand.heal_is_aoe(3) and ScopeBand.heal_is_aoe(5):
                _ok("a heal is a friendly AoE from the epic band up (levels 3-5)")
        else:
                _fail("the epic band did not turn the heal into an AoE")
        if ScopeBand.heal_max_targets(2) == 1 and ScopeBand.heal_max_targets(5) == 0:
                _ok("the heal cap lifts to unlimited at the top (rare=1, mythic=0/unlimited)")
        else:
                _fail("the heal target cap is wrong: rare=%d mythic=%d" % [ScopeBand.heal_max_targets(2), ScopeBand.heal_max_targets(5)])
        if ScopeBand.heal_radius(3) > 0.0 and ScopeBand.heal_radius(5) > ScopeBand.heal_radius(3):
                _ok("the heal AoE radius widens with the band (epic %.0f -> mythic %.0f)" % [ScopeBand.heal_radius(3), ScopeBand.heal_radius(5)])
        else:
                _fail("the heal AoE radius did not widen across bands")

        # --- 2. The teleport band: reach climbs, mythic crosses scope ---
        var reaches: Array[float] = []
        for lvl in range(1, 6):
                reaches.append(ScopeBand.teleport_range(lvl))
        var monotonic := true
        for i in range(1, reaches.size()):
                if reaches[i] <= reaches[i - 1]:
                        monotonic = false
        if monotonic:
                _ok("teleport reach climbs every tier (%s m)" % str(reaches))
        else:
                _fail("teleport reach is not monotonic across tiers: %s" % str(reaches))
        if ScopeBand.teleport_range(4) >= 10000.0:
                _ok("the legendary band folds ~10 km (%.0f m)" % ScopeBand.teleport_range(4))
        else:
                _fail("the legendary teleport band is under 10 km (%.0f m)" % ScopeBand.teleport_range(4))
        if not ScopeBand.teleport_crosses_scope(4) and ScopeBand.teleport_crosses_scope(5):
                _ok("only the mythic band crosses scopes (legendary stays local)")
        else:
                _fail("the scope-crossing boundary is wrong (legendary crosses=%s mythic crosses=%s)" % [ScopeBand.teleport_crosses_scope(4), ScopeBand.teleport_crosses_scope(5)])
        if ScopeBand.teleport_scope(5) == ScopeBand.PLANET:
                _ok("the mythic teleport reaches PLANET scope")
        else:
                _fail("the mythic teleport scope is %s, expected planet" % ScopeBand.scope_name(ScopeBand.teleport_scope(5)))

        # --- 3. Skill wiring: apply_scope_bands folds the tables in ---
        var ds = root.get_node_or_null("DataService")
        if ds == null:
                _fail("DataService autoload missing")
                _finish()
                return
        var nova_schema = ds.get_skill("human_cleric_holy_nova")
        if nova_schema == null:
                _fail("human_cleric_holy_nova did not load")
        else:
                var rare = CombatSkill.from_schema(nova_schema)
                rare.scope_bands = true
                rare.upgrade_level = 2
                rare.apply_scope_bands()
                if not rare.heal_aoe:
                        _ok("holy_nova at the rare band is still single-target")
                else:
                        _fail("holy_nova went AoE at the rare band")
                var epic = CombatSkill.from_schema(nova_schema)
                epic.scope_bands = true
                epic.upgrade_level = 3
                epic.apply_scope_bands()
                if epic.heal_aoe and epic.heal_max_targets == 0 and epic.heal_aoe_radius > 0.0:
                        _ok("holy_nova at the epic band is an uncapped friendly AoE (r=%.0f)" % epic.heal_aoe_radius)
                else:
                        _fail("holy_nova at epic did not become an uncapped AoE (aoe=%s cap=%d r=%.1f)" % [epic.heal_aoe, epic.heal_max_targets, epic.heal_aoe_radius])

        var phase_schema = ds.get_skill("akkan_seer_phase_shift")
        if phase_schema == null:
                _fail("akkan_seer_phase_shift did not load")
        else:
                var blink = CombatSkill.from_schema(phase_schema)
                blink.upgrade_level = 5
                blink.apply_scope_bands()
                if blink.teleport_distance >= 50000.0 and blink.teleport_scope == ScopeBand.PLANET:
                        _ok("phase_shift at the mythic band reaches %.0f m across PLANET scope" % blink.teleport_distance)
                else:
                        _fail("phase_shift at mythic is %.0f m / scope %s" % [blink.teleport_distance, ScopeBand.scope_name(blink.teleport_scope)])

        # --- 4. LIVE banded heal over the real EntityService sweep ---
        # No globe boot: EntityService is an autoload, and the sweep only
        # needs registered bodies with a position. Keeps the receipt fast and
        # free of world-AI noise.
        var es := root.get_node_or_null("EntityService")
        if es == null:
                _fail("EntityService autoload missing")
                _finish()
                return

        var caster: Node = EntityScript.new()
        caster.display_name = "BandCaster"
        caster.entity_type = 1  # Entity.EntityType.PLAYER
        caster.relation = 0     # NEUTRAL
        root.add_child(caster)
        var origin: Vector3 = Vector3(500, 0, 500)
        caster.global_position = origin

        var friends: Array = []
        for i in range(2):
                var f: Node = EntityScript.new()
                f.display_name = "BandFriend%d" % i
                f.entity_type = 1  # PLAYER (friend)
                f.relation = 0     # NEUTRAL, same as the caster
                root.add_child(f)
                f.global_position = origin + Vector3(2.0 + i, 0, 0)
                es.register_entity(f)
                friends.append(f)

        var foe: Node = EntityScript.new()
        foe.display_name = "BandFoe"
        foe.entity_type = 2  # Entity.EntityType.ENEMY
        foe.relation = 1     # HOSTILE
        root.add_child(foe)
        foe.global_position = origin + Vector3(3.0, 0, 0)
        es.register_entity(foe)
        # _ready() recomputes max_health/current_health, so seat the wounded
        # values AFTER the nodes enter the tree.
        caster.current_health = caster.max_health
        for f in friends:
                f.current_health = 30
        foe.current_health = 30
        await physics_frame

        var heal = CombatSkill.new()
        heal.skill_id = "test_band_heal"
        heal.skill_name = "Test Band Heal"
        heal.heal_amount = 20
        heal.scope_bands = true
        heal.upgrade_level = 3
        heal.apply_scope_bands()
        heal.execute(caster, null)

        var friend_healed := 0
        for f in friends:
                if f.current_health > 30:
                        friend_healed += 1
        if friend_healed == 2:
                _ok("the epic-band heal mended every friendly in reach (2/2)")
        else:
                _fail("the banded heal mended %d/2 friends" % friend_healed)
        if foe.current_health == 30:
                _ok("the banded heal did not mend the hostile in the same radius")
        else:
                _fail("the banded heal mended a hostile (hp %d)" % foe.current_health)

        # --- 5. Base band stays single-target (no ally sweep) ---
        for f in friends:
                f.current_health = 30
        var single = CombatSkill.new()
        single.skill_id = "test_single_heal"
        single.skill_name = "Test Single Heal"
        single.heal_amount = 20
        single.scope_bands = true
        single.upgrade_level = 0
        single.apply_scope_bands()
        single.execute(caster, null)
        var single_healed := 0
        for f in friends:
                if f.current_health > 30:
                        single_healed += 1
        if single_healed == 0:
                _ok("the base-band heal does not sweep allies (single-target)")
        else:
                _fail("the base-band heal mended %d allies -- it should stay single-target" % single_healed)

        # --- 6. Banding is opt-in: an un-opted heal never becomes an AoE ---
        for f in friends:
                f.current_health = 30
        var plain = CombatSkill.new()
        plain.skill_id = "test_plain_heal"
        plain.skill_name = "Test Plain Heal"
        plain.heal_amount = 20
        plain.upgrade_level = 5  # top band
        plain.apply_scope_bands()
        if not plain.heal_aoe and plain.heal_max_targets == 1:
                _ok("a heal with scope_bands off stays single-target even at the top band")
        else:
                _fail("an un-opted heal went AoE (aoe=%s cap=%d)" % [plain.heal_aoe, plain.heal_max_targets])
        plain.execute(caster, null)
        var plain_healed := 0
        for f in friends:
                if f.current_health > 30:
                        plain_healed += 1
        if plain_healed == 0:
                _ok("an un-opted top-band heal still sweeps no allies")
        else:
                _fail("an un-opted heal mended %d allies" % plain_healed)

        # --- 7. An authored ring (aoe_radius) is inherently an AoE heal ---
        for f in friends:
                f.current_health = 30
        foe.current_health = 30
        var nova = CombatSkill.new()
        nova.skill_id = "test_nova_heal"
        nova.skill_name = "Test Nova Heal"
        nova.heal_amount = 20
        nova.aoe_radius = 6.0
        nova.upgrade_level = 0  # no band; the ring is authored, not banded
        nova.apply_scope_bands()
        nova.execute(caster, null)
        var nova_healed := 0
        for f in friends:
                if f.current_health > 30:
                        nova_healed += 1
        if nova_healed == 2:
                _ok("a heal with an authored aoe_radius sweeps allies with no band opt-in (2/2)")
        else:
                _fail("the authored-ring heal mended %d/2 allies" % nova_healed)
        if foe.current_health == 30:
                _ok("the authored-ring heal still never mends a hostile")
        else:
                _fail("the authored-ring heal mended a hostile (hp %d)" % foe.current_health)

        _finish()
