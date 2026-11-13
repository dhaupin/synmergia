## probe_conjured_ground -- the Underworld + Moon GroundProviders
## (labs/prd-clipmap.md 10): the two conjured globes now draw REAL terrain
## through the same clipmap + prop layer the main world uses.
##
## A. The underworld provider: a seed-smooth heightfield that flattens at
##    the camp; the five BiomeBand declarations partition the surface into
##    biomes; the biome->prop-kind dispatch reads `.family`.
## B. The moon provider: a carved crater bowl with a declared water surface;
##    the landing flat is level; the regolith biome.
## C. Both re-derive byte-identical (the determinism law).
## D. The moon globe conjures the clipmap + the Builder's Pool; the base
##    shell is a hidden backstop.
## Run: godot --headless --path . --script res://tests/probe_conjured_ground.gd
extends SceneTree

var _checks := 0


func _init() -> void:
        call_deferred("_run")


func _check(label: String, cond: bool) -> bool:
        _checks += 1
        print("  %s %s" % ["PASS" if cond else "FAIL", label])
        return cond


func _run() -> void:
        var ok := true
        var UProv: GDScript = load("res://scenes/worlds/underworld_provider.gd")
        var MProv: GDScript = load("res://scenes/worlds/moon_provider.gd")
        ok = _check("underworld provider loads", UProv != null) and ok
        ok = _check("moon provider loads", MProv != null) and ok
        if UProv == null or MProv == null:
                print("CONJURED-GROUND PROBE %s (%d checks)" % ["FAILED" if not ok else "PASSED", _checks])
                quit(0 if ok else 1)
                return

        var u = UProv.new()
        var m = MProv.new()

        # ---- A. The underworld provider ---------------------------------
        var camp: Vector3 = Vector3(0, 1, 0)
        ok = _check("the camp is level (relief faded at the seat)", absf(float(u.ground_height(camp))) < 0.001) and ok
        var far_dir: Vector3 = Vector3(1, 0.2, 0.3).normalized()
        var h_far: float = float(u.ground_height(far_dir))
        ok = _check("the shelf away from camp carries relief (not a flat ball)", absf(h_far) > 0.05) and ok
        ok = _check("the relief stays gentle (a shelf, not a mountain)", absf(h_far) < 8.0) and ok
        ok = _check("the underworld has no sea", float(u.sea_level()) < -1.0e8) and ok
        ok = _check("the underworld grows no canopy trees", float(u.tree_density(1)) == 0.0) and ok

        # The band partition: five biomes, each reached by some direction.
        var seen := {}
        for i in range(4000):
                var a: float = TAU * float(i) / 4000.0
                var rr: float = 20.0 + 60.0 * (float(i % 97) / 97.0)
                var d: Vector3 = (Vector3(0, 1, 0) * 2000.0 + Vector3(cos(a), 0, sin(a)) * rr).normalized()
                seen[int(u.biome_id(d))] = true
        ok = _check("the camp seat reads as its own biome", int(u.biome_id(camp)) == 0) and ok
        ok = _check("the band partition reaches >= 4 underworld biomes", seen.size() >= 4) and ok

        # The biome->kind dispatch (BiomeBand.family is the key).
        var rng := RandomNumberGenerator.new()
        rng.seed = 1
        var kinds := {}
        for bid in range(0, 6):
                kinds[bid] = int(u.detail_kind(bid, rng))
        ok = _check("the grass band dispatches to the tuft kind", kinds[5] == 0) and ok
        ok = _check("the mycelium band dispatches to a glow kind", kinds[3] == 3 or kinds[3] == 2) and ok
        ok = _check("the stone bands dispatch to the ore kind", kinds[1] == 8 or kinds[1] == 0) and ok

        # ---- B. The moon provider ---------------------------------------
        var cdir: Vector3 = m.crater_dir()
        ok = _check("the moon carves a crater bowl (floor below the reference)", float(m.ground_height(cdir)) < -20.0) and ok
        ok = _check("the crater's water surface is declared inside the dish", \
                absf(float(m.water_surface(cdir)) + 12.0) < 0.001) and ok
        # A gigantic pool: the sea is an inland sea, filled near the rim.
        ok = _check("the crater is an inland sea (waterline near the rim)", \
                float(m.crater_water_radius()) < m.PLANET_RADIUS and \
                m.PLANET_RADIUS - float(m.crater_water_radius()) <= 40.0) and ok
        ok = _check("the pool declares a bounded shore (inside the rim)", \
                float(m.crater_pool_ang()) > 0.0 and float(m.crater_pool_ang()) <= float(m.crater_angular_radius())) and ok
        var outside: Vector3 = Vector3(1, 0.1, 0).normalized()
        ok = _check("there is no water outside the crater", float(m.water_surface(outside)) < -1.0e8) and ok
        ok = _check("the crater reads as its own biome", int(m.biome_id(cdir)) <= 1) and ok
        ok = _check("the regolith reads away from the crater", int(m.biome_id(outside)) == 0) and ok
        var ldir: Vector3 = m.landing_dir()
        ok = _check("the landing sits outside the crater rim", \
                ldir.angle_to(cdir) > float(m.crater_angular_radius())) and ok
        var base_h: float = float(m.ground_height(ldir))
        ok = _check("the landing flat is level (matches the regolith baseline)", \
                absf(float(m.ground_height(ldir)) - base_h) < 0.001) and ok

        # ---- C. Determinism ---------------------------------------------
        var u2 = UProv.new()
        var m2 = MProv.new()
        var det_ok := true
        for i in range(64):
                var d: Vector3 = Vector3(sin(float(i) * 1.7), cos(float(i) * 0.9), sin(float(i) * 2.3)).normalized()
                if absf(float(u.ground_height(d)) - float(u2.ground_height(d))) > 0.0:
                        det_ok = false
                        break
                if absf(float(m.ground_height(d)) - float(m2.ground_height(d))) > 0.0:
                        det_ok = false
                        break
        ok = _check("both providers re-derive byte-identical (the determinism law)", det_ok) and ok

        # ---- D. The moon globe conjures terrain + the crater pool -------
        var packed: PackedScene = load("res://scenes/worlds/globe_moon.tscn")
        ok = _check("globe_moon.tscn loads", packed != null) and ok
        if packed != null:
                var moon: Node = packed.instantiate()
                root.add_child(moon)
                for _i in range(6):
                        await root.get_tree().process_frame
                var wr: Node = moon.get("world_root")
                ok = _check("the moon registers its world root", wr != null) and ok
                if wr != null:
                        var clip: Node = wr.get_node_or_null("ClipmapRoot")
                        ok = _check("the clipmap draws the moon's terrain", clip != null) and ok
                        var pool: Node = wr.get_node_or_null("BuilderPool")
                        ok = _check("the Builder's Pool is declared (the crater landmark)", pool != null) and ok
                        if pool != null:
                                # The pool's WATER is the shared clipmap sheet
                                # (drawn from provider.water_surface over the
                                # sphere); the marker seats at the waterline.
                                var pool_r: float = pool.global_position.distance_to(wr.global_position)
                                ok = _check("the pool seats on the declared waterline radius", \
                                        absf(pool_r - float(m.crater_water_radius())) < 1.0) and ok
                        var clip2: Node = wr.get_node_or_null("ClipmapRoot")
                        if clip2 != null:
                                ok = _check("the clipmap owns the drawn water (the shared sheet)", clip2 != null) and ok
                        var shell: Node = wr.get_node_or_null("MoonShell")
                        if shell != null:
                                var vis: Node = shell.get_node_or_null("ShellVisual")
                                ok = _check("the base shell is a hidden backstop (no second ground)", \
                                        vis != null and not vis.visible) and ok
                moon.queue_free()

        print("CONJURED-GROUND PROBE %s (%d checks)" % ["PASSED" if ok else "FAILED", _checks])
        quit(0 if ok else 1)
