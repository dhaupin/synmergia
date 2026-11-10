extends SceneTree

## Probe: the training dummy .glb loads as a real static mesh -- at
## least one MeshInstance3D with surface(s) and an assigned material --
## and enemy_training_dummy.tres points at it. The dummy is static
## (no skeleton, no clips). Exit 0 = all good.
##
## _initialize(), not _init(): the data-wiring section resolves the
## DataService autoload, which attaches after _init.

func _initialize() -> void:
        var scene: PackedScene = load("res://models/enemies/enemy_training_dummy.glb")
        if scene == null:
                push_error("FAIL: training dummy glb did not load")
                quit(1)
                return
        var inst := scene.instantiate()
        inst.name = "enemy_training_dummy"
        root.add_child(inst)

        # Real geometry: at least one MeshInstance3D with a mesh that has
        # surface(s) and a material assigned.
        var mesh_inst := _find_mesh(inst)
        if mesh_inst == null or mesh_inst.mesh == null:
                push_error("FAIL: no MeshInstance3D with a mesh")
                quit(1)
                return
        if mesh_inst.mesh.get_surface_count() < 1:
                push_error("FAIL: mesh has no surfaces")
                quit(1)
                return
        if mesh_inst.mesh.surface_get_material(0) == null:
                push_error("FAIL: mesh surface has no material")
                quit(1)
                return
        var aabb := mesh_inst.mesh.get_aabb()
        print("[OK] mesh: %d surface(s), material=%s, aabb size=%s" % [
                mesh_inst.mesh.get_surface_count(),
                mesh_inst.mesh.surface_get_material(0).resource_name,
                str(aabb.size)])
        if aabb.size.x <= 0.0 or aabb.size.y <= 0.0 or aabb.size.z <= 0.0:
                push_error("FAIL: mesh has zero-extent bounds")
                quit(1)
                return
        print("[OK] dummy mesh has real extent")

        # The dummy is static: no skeleton, no animation clips.
        if _find_skel(inst) != null:
                push_error("FAIL: dummy should not carry a skeleton")
                quit(1)
                return
        print("[OK] static mesh (no skeleton)")

        # Training-dummy data wires the model + the dummy hitbox.
        var ds = root.get_node_or_null("DataService")
        if ds == null:
                push_error("FAIL: no DataService")
                quit(1)
                return
        if not ds._loaded:
                ds.load_all_data()
        var dummy = ds.get_enemy("training_dummy")
        if dummy == null:
                push_error("FAIL: enemy_training_dummy data missing")
                quit(1)
                return
        var mp = dummy.get("model_path")
        if mp == null or str(mp) != "res://models/enemies/enemy_training_dummy.glb":
                push_error("FAIL: dummy model_path not wired: %s" % str(mp))
                quit(1)
                return
        var hp = dummy.get("hitbox_profile_id")
        if hp == null or str(hp) != "hitbox_dummy":
                push_error("FAIL: dummy hitbox_profile_id not dummy: %s" % str(hp))
                quit(1)
                return
        print("[OK] enemy_training_dummy.tres -> enemy_training_dummy.glb + hitbox_dummy")
        inst.free()
        print("--- TRAINING DUMMY MODEL PROBE: ok=true ---")
        quit(0)

func _find_skel(n: Node) -> Skeleton3D:
        if n is Skeleton3D:
                return n
        for c in n.get_children():
                var s := _find_skel(c)
                if s != null:
                        return s
        return null

func _find_mesh(n: Node) -> MeshInstance3D:
        if n is MeshInstance3D and n.mesh != null:
                return n
        for c in n.get_children():
                var m := _find_mesh(c)
                if m != null:
                        return m
        return null
